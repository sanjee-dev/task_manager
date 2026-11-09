<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

class RegistrationCredentialsNotification extends Notification
{
    use Queueable;

    public function __construct(
        public readonly string $username,
        public readonly string $password,
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
        return (new MailMessage)
            ->subject('Your Task Manager login credentials')
            ->greeting('Welcome to Task Manager, '.$notifiable->name.'!')
            ->line('Your account is ready. Use the credentials below to sign in.')
            ->line('Username: '.$this->username)
            ->line('Password: '.$this->password)
            ->line('Your password is permanent until you change or reset it.')
            ->line('You can sign in to Task Manager using your username and password.');
    }
}
