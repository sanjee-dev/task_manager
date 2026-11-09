<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Task;
use App\Models\TaskSyncMutation;
use App\Models\User;
use App\Notifications\RegistrationCredentialsNotification;
use Illuminate\Auth\Events\PasswordReset;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Laravel\Sanctum\PersonalAccessToken;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
        ]);

        try {
            $user = DB::transaction(function () use ($validated): User {
                $isFirstUser = ! User::query()->exists();
                $username = $this->uniqueUsername($validated['name']);
                $password = $this->generatePassword();
                $user = User::query()->create([
                    'name' => $validated['name'],
                    'email' => $validated['email'],
                    'username' => $username,
                    'password' => $password,
                ]);
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

                Notification::send(
                    $user,
                    new RegistrationCredentialsNotification($username, $password),
                );

                return $user;
            });
        } catch (TransportExceptionInterface) {
            return response()->json([
                'message' => 'Your account could not be created because the credentials email could not be delivered. Please try again later.',
            ], 503);
        }

        return response()->json([
            'message' => 'Your account is ready. Check your email for your username and password.',
            'data' => ['email' => $user->email],
        ], 201);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'username' => ['required', 'string'],
            'password' => ['required', 'string'],
        ]);
        $user = User::query()->where('username', $validated['username'])->first();

        if ($user === null || ! Hash::check($validated['password'], $user->password)) {
            return response()->json(['message' => 'The provided credentials are incorrect.'], 401);
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

        try {
            $status = Password::sendResetLink(['email' => $validated['email']]);
        } catch (TransportExceptionInterface) {
            return response()->json([
                'message' => 'The password reset email could not be sent. Please try again later.',
            ], 503);
        }

        if ($status === Password::RESET_THROTTLED) {
            return response()->json([
                'message' => 'A reset link was recently requested. Please wait before trying again.',
            ], 429);
        }

        return response()->json([
            'message' => 'If an account exists for that email, a password reset link will be sent.',
        ]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $request->merge(['email' => Str::lower((string) $request->input('email'))]);
        $validated = $request->validate([
            'email' => ['required', 'email'],
            'token' => ['required', 'string'],
            'password' => ['required', 'confirmed', $this->passwordRule()],
        ]);

        $status = Password::reset(
            $validated,
            function (User $user, string $password): void {
                $user->forceFill(['password' => $password])->save();
                $user->tokens()->delete();
                event(new PasswordReset($user));
            },
        );

        if ($status !== Password::PASSWORD_RESET) {
            return response()->json([
                'message' => 'The password reset link is invalid or expired.',
            ], 422);
        }

        return response()->json([
            'message' => 'Your password has been reset. Please sign in.',
        ]);
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
            $user->forceFill(['password' => $validated['password']])->save();
            $currentToken = $request->user()->currentAccessToken();
            if ($currentToken instanceof PersonalAccessToken) {
                $user->tokens()->whereKeyNot($currentToken->getKey())->delete();
            }
        });

        return response()->json(['message' => 'Your password has been updated.']);
    }

    private function uniqueUsername(string $name): string
    {
        $base = trim(preg_replace(
            '/[^a-z0-9]+/',
            '_',
            Str::ascii(Str::lower($name)),
        ) ?? '', '_');
        $base = substr($base === '' ? 'user' : $base, 0, 40);

        do {
            $username = $base.'_'.Str::lower(Str::random(8));
        } while (User::query()->where('username', $username)->exists());

        return $username;
    }

    private function generatePassword(): string
    {
        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-_=+[]{}';
        $symbols = '!@#$%^&*()-_=+[]{}';
        $characters = [
            chr(random_int(65, 90)),
            chr(random_int(97, 122)),
            chr(random_int(48, 57)),
            $symbols[random_int(0, strlen($symbols) - 1)],
        ];

        for ($index = count($characters); $index < 32; $index++) {
            $characters[] = $alphabet[random_int(0, strlen($alphabet) - 1)];
        }

        for ($index = count($characters) - 1; $index > 0; $index--) {
            $swapIndex = random_int(0, $index);
            [$characters[$index], $characters[$swapIndex]] = [
                $characters[$swapIndex],
                $characters[$index],
            ];
        }

        return implode('', $characters);
    }

    private function passwordRule(): PasswordRule
    {
        return PasswordRule::min(12)->mixedCase()->letters()->numbers()->symbols();
    }

    /**
     * @return array{id: int, name: string, email: string, username: string}
     */
    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'username' => $user->username,
        ];
    }
}
