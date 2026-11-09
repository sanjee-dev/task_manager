<?php

namespace Tests\Feature;

use App\Models\User;
use App\Notifications\AuthOtpNotification;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class AuthApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_registration_verification_and_login_flow(): void
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
            'password' => 'StrongPassword123!',
            'password_confirmation' => 'StrongPassword123!',
        ])->assertCreated()
            ->assertJsonPath('data.email', $email);

        $user = User::query()->where('email', $email)->firstOrFail();
        $this->assertDatabaseHas('tasks', [
            'id' => '10101010-1010-4010-8010-101010101010',
            'user_id' => $user->id,
        ]);
        $this->assertTrue(Hash::check('StrongPassword123!', $user->password));
        $this->assertDatabaseHas('auth_otps', [
            'user_id' => $user->id,
            'purpose' => 'email_verification',
        ]);
        $otp = $this->notificationCode($user, 'email_verification');

        $this->postJson('/api/verify-email-otp', [
            'email' => $email,
            'otp' => $otp,
        ])->assertOk();
        $this->postJson('/api/verify-email-otp', [
            'email' => $email,
            'otp' => $otp,
        ])->assertUnprocessable();

        $this->postJson('/api/login', [
            'email' => $email,
            'password' => 'StrongPassword123!',
        ])->assertOk()
            ->assertJsonStructure(['data' => ['token', 'user' => ['id', 'name', 'email']]]);
    }

    public function test_login_rejects_bad_credentials_and_unverified_accounts(): void
    {
        $user = User::factory()->create([
            'email' => 'unverified@example.test',
            'password' => 'StrongPassword123!',
            'email_verified_at' => null,
        ]);

        $this->postJson('/api/login', [
            'email' => $user->email,
            'password' => 'WrongPassword123!',
        ])->assertUnauthorized();
        $this->postJson('/api/login', [
            'email' => $user->email,
            'password' => 'StrongPassword123!',
        ])->assertForbidden();
    }

    public function test_authenticated_profile_logout_and_password_change(): void
    {
        $user = User::factory()->create([
            'email_verified_at' => now(),
            'password' => 'StrongPassword123!',
        ]);
        $currentToken = $user->createToken('test');
        $token = $currentToken->plainTextToken;
        $secondToken = $user->createToken('other-device')->accessToken;

        $this->withToken($token)->getJson('/api/user')
            ->assertOk()
            ->assertJsonPath('data.email', $user->email);
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

    public function test_password_reset_uses_one_time_otp_and_reset_token(): void
    {
        Notification::fake();
        $user = User::factory()->create([
            'email' => 'reset@example.test',
            'email_verified_at' => now(),
            'password' => 'InitialPassword123!',
        ]);
        $this->postJson('/api/forgot-password', ['email' => $user->email])
            ->assertOk()
            ->assertJsonPath('message', 'If an eligible account exists, a reset code has been sent.');
        $otp = $this->notificationCode($user, 'password_reset');

        $response = $this->postJson('/api/verify-reset-otp', [
            'email' => $user->email,
            'otp' => $otp,
        ])->assertOk();
        $resetToken = $response->json('data.reset_token');

        $this->postJson('/api/reset-password', [
            'email' => $user->email,
            'reset_token' => $resetToken,
            'password' => 'ReplacementPassword123!',
            'password_confirmation' => 'ReplacementPassword123!',
        ])->assertOk();
        $this->postJson('/api/reset-password', [
            'email' => $user->email,
            'reset_token' => $resetToken,
            'password' => 'ThirdPassword123!',
            'password_confirmation' => 'ThirdPassword123!',
        ])->assertUnprocessable();
        $this->assertTrue(Hash::check('ReplacementPassword123!', $user->fresh()->password));
    }

    public function test_forgot_password_does_not_disclose_unknown_accounts(): void
    {
        Notification::fake();
        $this->postJson('/api/forgot-password', ['email' => 'missing@example.test'])
            ->assertOk()
            ->assertJsonPath('message', 'If an eligible account exists, a reset code has been sent.');
        Notification::assertNothingSent();
    }

    public function test_expired_sanctum_tokens_are_rejected(): void
    {
        $user = User::factory()->create(['email_verified_at' => now()]);
        $issuedToken = $user->createToken('expired');
        $issuedToken->accessToken->forceFill([
            'created_at' => now()->subMinutes(2),
        ])->save();
        config(['sanctum.expiration' => 1]);

        $this->withToken($issuedToken->plainTextToken)
            ->getJson('/api/user')
            ->assertUnauthorized();
    }

    private function notificationCode(User $user, string $purpose): string
    {
        $code = null;
        Notification::assertSentTo(
            $user,
            AuthOtpNotification::class,
            function (AuthOtpNotification $notification) use ($purpose, &$code): bool {
                if ($notification->purpose !== $purpose) {
                    return false;
                }
                $code = $notification->code;

                return true;
            },
        );
        $this->assertNotNull($code);

        return $code;
    }
}
