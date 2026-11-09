<?php

namespace App\Notifications;

use Illuminate\Auth\Notifications\ResetPassword;

class TaskManagerPasswordResetNotification extends ResetPassword
{
    public function toMail($notifiable)
    {
        return parent::toMail($notifiable)
            ->line('Your Task Manager username is: '.$notifiable->username);
    }
}
