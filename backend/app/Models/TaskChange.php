<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TaskChange extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'id',
        'task_uuid',
        'version',
    ];
}
