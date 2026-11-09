<?php

namespace Tests\Feature;

use App\Models\User;
use App\Notifications\RegistrationCredentialsNotification;
use App\Notifications\TaskManagerPasswordResetNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Symfony\Component\Mailer\Exception\TransportException;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_generates_credentials_emails_them_and_allows_username_login(): void
    {
        Notification::fake();
        $email = 'new-user@example.test';
        DB::table('tasks')->insert([
            'id' => '10101010-1010-4010-8010-101010101010',
            'title' => 'Legacy server task',
            'note' => null,
            'start_datetime' => '2026-11-05 09:00:00',
            'end_datetime' => '2026-11-05 10:00:00',
            'status' => 'pending',
            'version' => 1,
            'created_at' => now(),
            'updated_at' => now(),
            'deleted_at' => null,
        ]);

        $this->postJson('/api/register', [
            'name' => 'New User',
            'email' => $email,
        ])->assertCreated()
            ->assertJsonPath('data.email', $email)
            ->assertJsonMissingPath('data.password');

        $user = User::query()->where('email', $email)->firstOrFail();
        $this->assertNotEmpty($user->username);
        $this->assertDatabaseHas('tasks', [
            'id' => '10101010-1010-4010-8010-101010101010',
            'user_id' => $user->id,
        ]);

        $credentials = null;
        Notification::assertSentTo(
            $user,
            RegistrationCredentialsNotification::class,
            function (RegistrationCredentialsNotification $notification) use (&$credentials): bool {
                $credentials = $notification;

                return true;
            },
        );
        $this->assertNotNull($credentials);
        $this->assertSame($user->username, $credentials->username);
        $registrationEmail = $credentials->toMail($user);
        $this->assertContains(
            'Username: '.$user->username,
            [...$registrationEmail->introLines, ...$registrationEmail->outroLines],
        );
        $this->assertContains(
            'Password: '.$credentials->password,
            [...$registrationEmail->introLines, ...$registrationEmail->outroLines],
        );
        $this->assertMatchesRegularExpression(
            '/^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9]).{32}$/',
            $credentials->password,
        );
        $this->assertTrue(Hash::check($credentials->password, $user->password));
        $this->assertDatabaseMissing('auth_otps', ['user_id' => $user->id]);

        $this->postJson('/api/login', [
            'username' => $credentials->username,
            'password' => $credentials->password,
        ])->assertOk()
            ->assertJsonStructure(['data' => ['token', 'user' => ['id', 'name', 'email', 'username']]]);

        $this->postJson('/api/login', [
            'email' => $email,
            'password' => $credentials->password,
        ])->assertUnprocessable();

        $this->postJson('/api/register', [
            'name' => 'New User',
            'email' => 'new-user-two@example.test',
        ])->assertCreated();
        $secondUser = User::query()
            ->where('email', 'new-user-two@example.test')
            ->firstOrFail();
        $this->assertNotSame($user->username, $secondUser->username);
    }

    public function test_login_rejects_bad_credentials_and_does_not_require_email_verification(): void
    {
        $user = User::factory()->create([
            'email_verified_at' => null,
            'password' => 'StrongPassword123!',
        ]);

        $this->postJson('/api/login', [
            'username' => $user->username,
            'password' => 'WrongPassword123!',
        ])->assertUnauthorized();

        $this->postJson('/api/login', [
            'username' => $user->username,
            'password' => 'StrongPassword123!',
        ])->assertOk();
    }

    public function test_registration_does_not_claim_success_when_credentials_email_fails(): void
    {
        Notification::shouldReceive('send')
            ->once()
            ->andThrow(new TransportException('mail server unavailable'));

        $this->postJson('/api/register', [
            'name' => 'No Mail User',
            'email' => 'no-mail@example.test',
        ])->assertServiceUnavailable()
            ->assertJsonPath(
                'message',
                'Your account could not be created because the credentials email could not be delivered. Please try again later.',
            );

        $this->assertDatabaseMissing('users', ['email' => 'no-mail@example.test']);
    }

    public function test_authenticated_profile_logout_and_password_change(): void
    {
        $user = User::factory()->create(['password' => 'StrongPassword123!']);
        $currentToken = $user->createToken('test');
        $token = $currentToken->plainTextToken;
        $secondToken = $user->createToken('other-device')->accessToken;

        $this->withToken($token)->getJson('/api/user')
            ->assertOk()
            ->assertJsonPath('data.email', $user->email)
            ->assertJsonPath('data.username', $user->username);
        $this->withToken($token)->postJson('/api/change-password', [
            'current_password' => 'StrongPassword123!',
            'password' => 'AnotherStrong123!',
            'password_confirmation' => 'AnotherStrong123!',
        ])->assertOk();

        $this->assertDatabaseMissing('personal_access_tokens', ['id' => $secondToken->id]);
        $this->assertDatabaseHas('personal_access_tokens', [
            'id' => $currentToken->accessToken->id,
        ]);
        $this->withToken($token)->postJson('/api/logout')->assertOk();
        $this->assertDatabaseMissing('personal_access_tokens', ['tokenable_id' => $user->id]);
        $this->assertTrue(Hash::check('AnotherStrong123!', $user->fresh()->password));
    }

    public function test_password_reset_uses_the_single_use_expiring_email_link(): void
    {
        Notification::fake();
        $user = User::factory()->create([
            'email' => 'reset@example.test',
            'password' => 'InitialPassword123!',
        ]);
        $user->createToken('existing-session');

        $this->postJson('/api/forgot-password', ['email' => $user->email])
            ->assertOk()
            ->assertJsonPath(
                'message',
                'If an account exists for that email, a password reset link will be sent.',
            );

        $resetToken = null;
        $resetNotification = null;
        Notification::assertSentTo(
            $user,
            TaskManagerPasswordResetNotification::class,
            function (TaskManagerPasswordResetNotification $notification) use (&$resetToken, &$resetNotification): bool {
                $resetToken = $notification->token;
                $resetNotification = $notification;

                return true;
            },
        );
        $this->assertNotNull($resetToken);
        $resetEmail = $resetNotification->toMail($user);
        $this->assertContains(
            'Your Task Manager username is: '.$user->username,
            [...$resetEmail->introLines, ...$resetEmail->outroLines],
        );
        $this->get(route('password.reset', [
            'token' => $resetToken,
            'email' => $user->email,
        ]))->assertOk()->assertSee('Confirm new password');

        $this->post(route('password.update'), [
            'email' => $user->email,
            'token' => $resetToken,
            'password' => 'ReplacementPassword123!',
            'password_confirmation' => 'ReplacementPassword123!',
        ])->assertOk()->assertSee('Your password has been reset.');
        $this->postJson('/api/reset-password', [
            'email' => $user->email,
            'token' => $resetToken,
            'password' => 'ThirdPassword123!',
            'password_confirmation' => 'ThirdPassword123!',
        ])->assertUnprocessable();
        $this->assertTrue(Hash::check('ReplacementPassword123!', $user->fresh()->password));
        $this->assertDatabaseMissing('personal_access_tokens', ['tokenable_id' => $user->id]);
    }

    public function test_forgot_password_does_not_disclose_unknown_accounts(): void
    {
        Notification::fake();

        $this->postJson('/api/forgot-password', ['email' => 'missing@example.test'])
            ->assertOk()
            ->assertJsonPath(
                'message',
                'If an account exists for that email, a password reset link will be sent.',
            );
        Notification::assertNothingSent();
    }

    public function test_expired_password_reset_links_are_rejected(): void
    {
        Notification::fake();
        $user = User::factory()->create(['email' => 'expired-reset@example.test']);
        $this->postJson('/api/forgot-password', ['email' => $user->email])->assertOk();

        $resetToken = null;
        Notification::assertSentTo(
            $user,
            TaskManagerPasswordResetNotification::class,
            function (TaskManagerPasswordResetNotification $notification) use (&$resetToken): bool {
                $resetToken = $notification->token;

                return true;
            },
        );
        DB::table('password_reset_tokens')
            ->where('email', $user->email)
            ->update(['created_at' => now()->subMinutes(61)]);

        $this->postJson('/api/reset-password', [
            'email' => $user->email,
            'token' => $resetToken,
            'password' => 'ReplacementPassword123!',
            'password_confirmation' => 'ReplacementPassword123!',
        ])->assertUnprocessable();
        $this->assertTrue(Hash::check('password', $user->fresh()->password));
    }

    public function test_otp_routes_are_not_available(): void
    {
        $this->postJson('/api/verify-email-otp')->assertNotFound();
        $this->postJson('/api/resend-otp')->assertNotFound();
        $this->postJson('/api/verify-reset-otp')->assertNotFound();
    }

    public function test_expired_sanctum_tokens_are_rejected(): void
    {
        $user = User::factory()->create();
        $issuedToken = $user->createToken('expired');
        $issuedToken->accessToken->forceFill([
            'created_at' => now()->subMinutes(2),
        ])->save();
        config(['sanctum.expiration' => 1]);

        $this->withToken($issuedToken->plainTextToken)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }
}
