<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class AuthOtpNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly string $code,
        public readonly string $purpose,
    ) {}

    /**
     * @return list<string>
     */
    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $isPasswordReset = $this->purpose === 'password_reset';

        return (new MailMessage)
            ->subject($isPasswordReset ? 'Your password reset code' : 'Verify your Task Manager email')
            ->line($isPasswordReset
                ? 'Use this code to reset your Task Manager password.'
                : 'Use this code to verify your Task Manager email address.')
            ->line($this->code)
            ->line('This code expires in 10 minutes and can only be used once.')
            ->line('If you did not request this, you can ignore this email.');
    }
}
