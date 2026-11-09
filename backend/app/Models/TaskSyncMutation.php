<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TaskSyncMutation extends Model
{
    public $timestamps = false;

    protected $primaryKey = 'mutation_id';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'mutation_id',
        'user_id',
        'task_uuid',
        'request_hash',
        'response',
    ];

    protected function casts(): array
    {
        return ['response' => 'array'];
    }
}
