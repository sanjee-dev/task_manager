<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TaskChangeSequence extends Model
{
    protected $table = 'task_change_sequence';

    public $timestamps = false;

    public $incrementing = false;

    protected $fillable = ['id', 'value'];

    protected function casts(): array
    {
        return ['value' => 'integer'];
    }
}
