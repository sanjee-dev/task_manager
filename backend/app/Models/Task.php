<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Task extends Model
{
    use SoftDeletes;

    protected $keyType = 'string';

    public $incrementing = false;

    protected $fillable = [
        'id',
        'user_id',
        'updated_by_user_id',
        'title',
        'note',
        'start_datetime',
        'end_datetime',
        'status',
        'version',
    ];

    protected function casts(): array
    {
        return [
            'start_datetime' => 'immutable_datetime',
            'end_datetime' => 'immutable_datetime',
            'deleted_at' => 'immutable_datetime',
            'version' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
