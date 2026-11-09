<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Reset password - Task Manager</title>
    <style>
        body { font-family: system-ui, sans-serif; margin: 0; background: #f4f6fb; color: #172033; }
        main { box-sizing: border-box; max-width: 440px; margin: 8vh auto; padding: 28px; background: white; border-radius: 16px; }
        label { display: block; margin: 16px 0 6px; font-weight: 600; }
        input { box-sizing: border-box; width: 100%; padding: 12px; border: 1px solid #cbd2e0; border-radius: 8px; }
        button { margin-top: 20px; padding: 12px 18px; border: 0; border-radius: 8px; background: #315ee7; color: white; font-weight: 700; }
        .error { color: #a32020; }
    </style>
</head>
<body>
<main>
    <h1>Reset your password</h1>
    @if ($status)
        <p>{{ $status }}</p>
    @else
        <p>Choose a new password for your Task Manager account.</p>
        @if ($errors->any())
            <div class="error" role="alert">
                @foreach ($errors->all() as $error)
                    <p>{{ $error }}</p>
                @endforeach
            </div>
        @endif
        <form method="POST" action="{{ route('password.update') }}">
            @csrf
            <input type="hidden" name="token" value="{{ $token }}">
            <label for="email">Email address</label>
            <input id="email" name="email" type="email" value="{{ old('email', $email) }}" required autocomplete="email">
            <label for="password">New password</label>
            <input id="password" name="password" type="password" required autocomplete="new-password">
            <label for="password_confirmation">Confirm new password</label>
            <input id="password_confirmation" name="password_confirmation" type="password" required autocomplete="new-password">
            <button type="submit">Reset password</button>
        </form>
    @endif
</main>
</body>
</html>
