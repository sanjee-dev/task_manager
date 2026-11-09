<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AuthOtp;
use App\Models\Task;
use App\Models\TaskSyncMutation;
use App\Models\User;
use App\Notifications\AuthOtpNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;

class AuthController extends Controller
{
    private const OTP_TTL_MINUTES = 10;

    private const OTP_RESEND_SECONDS = 60;

    private const OTP_MAX_ATTEMPTS = 5;

    public function register(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'confirmed', $this->passwordRule()],
        ]);
        $validated['email'] = Str::lower($validated['email']);

        $user = DB::transaction(function () use ($validated): User {
            $isFirstUser = ! User::query()->exists();
            $user = User::query()->create($validated);
            if ($isFirstUser) {
                Task::query()->whereNull('user_id')->update(['user_id' => $user->id]);
                TaskSyncMutation::query()
                    ->whereNull('user_id')
                    ->whereIn(
                        'task_uuid',
                        Task::query()->select('id')->where('user_id', $user->id),
                    )
                    ->update(['user_id' => $user->id]);
            }

            return $user;
        });
        $sent = $this->issueOtp($user, 'email_verification');
        if (! $sent) {
            return response()->json([
                'message' => 'Email delivery is temporarily unavailable. Please try again.',
            ], 503);
        }

        return response()->json([
            'message' => 'A verification code has been sent to your email address.',
            'data' => ['email' => $user->email],
        ], 201);
    }

    public function verifyEmailOtp(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'otp' => ['required', 'digits:6'],
        ]);

        return DB::transaction(function () use ($validated): JsonResponse {
            $user = User::query()->where('email', $validated['email'])->lockForUpdate()->first();
            $otp = $user === null
                ? null
                : $this->latestUsableOtp($user, 'email_verification');

            if (! $this->verifyOtp($otp, $validated['otp'])) {
                return $this->invalidOtpResponse();
            }

            $otp->update(['consumed_at' => now()]);
            $user->forceFill(['email_verified_at' => now()])->save();

            return response()->json(['message' => 'Your email address is verified.']);
        });
    }

    public function resendOtp(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate(['email' => ['required', 'email']]);
        $user = User::query()->where('email', Str::lower($validated['email']))->first();

        if ($user !== null && $user->email_verified_at === null) {
            $this->issueOtp($user, 'email_verification');
        }

        return response()->json([
            'message' => 'If the account can receive a verification code, one has been sent.',
        ]);
    }

    public function login(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);
        $user = User::query()->where('email', Str::lower($validated['email']))->first();

        if ($user === null || ! Hash::check($validated['password'], $user->password)) {
            return response()->json(['message' => 'The provided credentials are incorrect.'], 401);
        }
        if ($user->email_verified_at === null) {
            return response()->json(['message' => 'Verify your email address before signing in.'], 403);
        }

        $token = $user->createToken('task-manager-mobile')->plainTextToken;

        return response()->json([
            'message' => 'Signed in successfully.',
            'data' => [
                'token' => $token,
                'user' => $this->userPayload($user),
            ],
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json(['message' => 'Signed out successfully.']);
    }

    public function user(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->userPayload($request->user())]);
    }

    public function forgotPassword(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate(['email' => ['required', 'email']]);
        $user = User::query()->where('email', Str::lower($validated['email']))->first();

        if ($user !== null && $user->email_verified_at !== null) {
            $this->issueOtp($user, 'password_reset');
        }

        return response()->json([
            'message' => 'If an eligible account exists, a reset code has been sent.',
        ]);
    }

    public function verifyResetOtp(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'otp' => ['required', 'digits:6'],
        ]);

        return DB::transaction(function () use ($validated): JsonResponse {
            $user = User::query()->where('email', $validated['email'])->lockForUpdate()->first();
            $otp = $user === null ? null : $this->latestUsableOtp($user, 'password_reset');

            if (! $this->verifyOtp($otp, $validated['otp'])) {
                return $this->invalidOtpResponse();
            }

            $resetToken = bin2hex(random_bytes(32));
            $otp->update([
                'verified_at' => now(),
                'consumed_at' => now(),
                'reset_token_hash' => Hash::make($resetToken),
            ]);

            return response()->json([
                'message' => 'Code verified.',
                'data' => ['reset_token' => $resetToken],
            ]);
        });
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'reset_token' => ['required', 'string', 'size:64'],
            'password' => ['required', 'confirmed', $this->passwordRule()],
        ]);

        return DB::transaction(function () use ($validated): JsonResponse {
            $user = User::query()->where('email', $validated['email'])->lockForUpdate()->first();
            $otp = $user === null ? null : AuthOtp::query()
                ->where('user_id', $user->id)
                ->where('purpose', 'password_reset')
                ->whereNotNull('verified_at')
                ->whereNotNull('reset_token_hash')
                ->where('expires_at', '>', now())
                ->latest('id')
                ->lockForUpdate()
                ->first();

            if ($otp === null || ! Hash::check($validated['reset_token'], $otp->reset_token_hash)) {
                return response()->json([
                    'message' => 'The password reset session is invalid or expired.',
                ], 422);
            }

            $user->forceFill(['password' => Hash::make($validated['password'])])->save();
            $user->tokens()->delete();
            $otp->update(['reset_token_hash' => null]);
            AuthOtp::query()
                ->where('user_id', $user->id)
                ->where('purpose', 'password_reset')
                ->whereNull('consumed_at')
                ->update(['consumed_at' => now()]);

            return response()->json([
                'message' => 'Your password has been reset. Please sign in.',
            ]);
        });
    }

    public function changePassword(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => ['required', 'confirmed', $this->passwordRule()],
        ]);
        $user = $request->user();

        if (! Hash::check($validated['current_password'], $user->password)) {
            return response()->json(['message' => 'The current password is incorrect.'], 422);
        }

        DB::transaction(function () use ($user, $request, $validated): void {
            $user->forceFill(['password' => Hash::make($validated['password'])])->save();
            $currentToken = $request->user()->currentAccessToken();
            if ($currentToken instanceof PersonalAccessToken) {
                $user->tokens()->whereKeyNot($currentToken->getKey())->delete();
            }
        });

        return response()->json(['message' => 'Your password has been updated.']);
    }

    private function issueOtp(User $user, string $purpose): bool
    {
        $issued = DB::transaction(function () use ($user, $purpose): ?array {
            User::query()->whereKey($user->id)->lockForUpdate()->firstOrFail();
            $latest = AuthOtp::query()
                ->where('user_id', $user->id)
                ->where('purpose', $purpose)
                ->whereNull('consumed_at')
                ->latest('id')
                ->lockForUpdate()
                ->first();
            if (
                $latest !== null &&
                $latest->last_sent_at->greaterThan(now()->subSeconds(self::OTP_RESEND_SECONDS))
            ) {
                return null;
            }

            $code = str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
            AuthOtp::query()
                ->where('user_id', $user->id)
                ->where('purpose', $purpose)
                ->whereNull('consumed_at')
                ->update(['consumed_at' => now()]);
            $otp = AuthOtp::query()->create([
                'user_id' => $user->id,
                'purpose' => $purpose,
                'otp_hash' => Hash::make($code),
                'expires_at' => now()->addMinutes(self::OTP_TTL_MINUTES),
                'last_sent_at' => now(),
            ]);

            return [$otp, $code];
        });
        if ($issued === null) {
            return false;
        }
        [$otp, $code] = $issued;

        try {
            Notification::send($user, new AuthOtpNotification($code, $purpose));
        } catch (TransportExceptionInterface) {
            $otp->update(['consumed_at' => now()]);

            return false;
        }

        return true;
    }

    private function latestUsableOtp(User $user, string $purpose): ?AuthOtp
    {
        return AuthOtp::query()
            ->where('user_id', $user->id)
            ->where('purpose', $purpose)
            ->whereNull('consumed_at')
            ->where('expires_at', '>', now())
            ->where('attempts', '<', self::OTP_MAX_ATTEMPTS)
            ->latest('id')
            ->lockForUpdate()
            ->first();
    }

    private function verifyOtp(?AuthOtp $otp, string $code): bool
    {
        if ($otp === null || ! Hash::check($code, $otp->otp_hash)) {
            if ($otp !== null) {
                $otp->increment('attempts');
                if ($otp->attempts >= self::OTP_MAX_ATTEMPTS) {
                    $otp->update(['consumed_at' => now()]);
                }
            }

            return false;
        }

        return true;
    }

    private function invalidOtpResponse(): JsonResponse
    {
        return response()->json(['message' => 'The code is invalid, expired, or has already been used.'], 422);
    }

    private function passwordRule(): PasswordRule
    {
        return PasswordRule::min(12)->mixedCase()->letters()->numbers()->symbols();
    }

    /**
     * @return array{id: int, name: string, email: string}
     */
    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
        ];
    }
}
