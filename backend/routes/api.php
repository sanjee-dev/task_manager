<?php

use App\Http\Controllers\Api\TaskSyncController;
use Illuminate\Support\Facades\Route;

Route::get('/v1/tasks', [TaskSyncController::class, 'index']);
Route::post('/v1/sync', [TaskSyncController::class, 'sync']);
