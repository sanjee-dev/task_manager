<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Resources\TaskResource;
use App\Models\Task;
use App\Models\TaskChange;
use App\Models\TaskChangeSequence;
use App\Models\TaskSyncMutation;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

class TaskSyncController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'cursor' => ['sometimes', 'integer', 'min:0'],
        ]);
        $cursor = (int) ($validated['cursor'] ?? 0);
        $userId = $request->user()->id;

        return DB::transaction(function () use ($cursor, $userId): JsonResponse {
            $changes = TaskChange::query()
                ->where('id', '>', $cursor)
                ->orderBy('id')
                ->limit(500)
                ->get(['id', 'task_uuid']);
            $nextCursor = (int) ($changes->last()?->id ?? $cursor);
            $latestChanges = $changes->groupBy('task_uuid')
                ->map(fn ($taskChanges) => $taskChanges->last());
            $tasks = Task::withTrashed()
                ->where('user_id', $userId)
                ->whereIn('id', $latestChanges->pluck('task_uuid'))
                ->get()
                ->keyBy('id');

            $data = $latestChanges->map(
                fn (TaskChange $change) => isset($tasks[$change->task_uuid])
                    ? (new TaskResource($tasks[$change->task_uuid]))->resolve()
                    : null,
            )->filter()->values();

            return response()->json([
                'data' => $data,
                'meta' => ['next_cursor' => $nextCursor],
            ]);
        });
    }

    public function sync(Request $request): JsonResponse
    {
        $userId = $request->user()->id;
        $validated = $request->validate([
            'mutations' => ['required', 'array', 'max:100'],
        ]);

        $results = [];
        foreach ($validated['mutations'] as $index => $mutation) {
            if (! is_array($mutation)) {
                $results[] = [
                    'index' => $index,
                    'status' => 'validation_error',
                    'errors' => ['mutation' => ['Each mutation must be an object.']],
                ];

                continue;
            }

            $validator = Validator::make($mutation, [
                'mutation_id' => ['required', 'uuid'],
                'task_uuid' => ['required', 'uuid'],
                'operation' => ['required', 'in:upsert,delete'],
                'base_version' => ['required', 'integer', 'min:0'],
                'task' => ['required_if:operation,upsert', 'array'],
                'task.title' => ['required_if:operation,upsert', 'string', 'max:255'],
                'task.note' => ['nullable', 'string'],
                'task.status' => ['required_if:operation,upsert', 'in:pending,done'],
                'task.start_datetime' => [
                    'required_if:operation,upsert',
                    'string',
                    'regex:/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,6})?(?:Z|[+-]\\d{2}:\\d{2})$/',
                    'date',
                ],
                'task.end_datetime' => [
                    'required_if:operation,upsert',
                    'string',
                    'regex:/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,6})?(?:Z|[+-]\\d{2}:\\d{2})$/',
                    'date',
                ],
            ]);

            if ($validator->fails()) {
                $results[] = [
                    'mutation_id' => $mutation['mutation_id'] ?? null,
                    'status' => 'validation_error',
                    'errors' => $validator->errors(),
                ];

                continue;
            }

            if (
                $mutation['operation'] === 'upsert'
                && strtotime($mutation['task']['end_datetime'])
                    < strtotime($mutation['task']['start_datetime'])
            ) {
                $results[] = [
                    'mutation_id' => $mutation['mutation_id'],
                    'status' => 'validation_error',
                    'errors' => [
                        'task.end_datetime' => ['The end date must be on or after the start date.'],
                    ],
                ];

                continue;
            }

            $results[] = $this->applyMutation($mutation, $userId);
        }

        return response()->json(['data' => $results]);
    }

    /**
     * @param  array<string, mixed>  $mutation
     * @return array<string, mixed>
     */
    private function applyMutation(array $mutation, int $userId): array
    {
        $requestHash = hash('sha256', json_encode(
            $this->canonicalize($mutation),
            JSON_THROW_ON_ERROR,
        ));

        $apply = function () use ($mutation, $requestHash, $userId): array {
            $existing = TaskSyncMutation::query()
                ->whereKey($mutation['mutation_id'])
                ->lockForUpdate()
                ->first();

            if ($existing !== null) {
                if ((int) $existing->user_id !== $userId) {
                    return [
                        'mutation_id' => $mutation['mutation_id'],
                        'status' => 'idempotency_key_reused',
                    ];
                }
                if (! hash_equals($existing->request_hash, $requestHash)) {
                    return [
                        'mutation_id' => $mutation['mutation_id'],
                        'status' => 'idempotency_key_reused',
                    ];
                }

                return $existing->response;
            }

            $task = Task::withTrashed()
                ->whereKey($mutation['task_uuid'])
                ->lockForUpdate()
                ->first();
            if ($task !== null && (int) $task->user_id !== $userId) {
                return [
                    'mutation_id' => $mutation['mutation_id'],
                    'task_uuid' => $mutation['task_uuid'],
                    'status' => 'forbidden',
                ];
            }
            $result = $this->applyTaskChange($mutation, $task, $userId);

            TaskSyncMutation::query()->create([
                'mutation_id' => $mutation['mutation_id'],
                'user_id' => $userId,
                'task_uuid' => $mutation['task_uuid'],
                'request_hash' => $requestHash,
                'response' => $result,
            ]);

            return $result;
        };

        try {
            return DB::transaction($apply);
        } catch (QueryException) {
            $existing = TaskSyncMutation::query()
                ->whereKey($mutation['mutation_id'])
                ->first();
            if ($existing !== null) {
                if ((int) $existing->user_id !== $userId) {
                    return [
                        'mutation_id' => $mutation['mutation_id'],
                        'status' => 'idempotency_key_reused',
                    ];
                }
                if (! hash_equals($existing->request_hash, $requestHash)) {
                    return [
                        'mutation_id' => $mutation['mutation_id'],
                        'status' => 'idempotency_key_reused',
                    ];
                }

                return $existing->response;
            }

            return DB::transaction($apply);
        }
    }

    /**
     * @param  array<string, mixed>  $mutation
     * @return array<string, mixed>
     */
    private function applyTaskChange(array $mutation, ?Task $task, int $userId): array
    {
        $baseVersion = (int) $mutation['base_version'];

        if ($task === null && $mutation['operation'] === 'upsert' && $baseVersion === 0) {
            $task = Task::query()->create([
                'id' => $mutation['task_uuid'],
                'user_id' => $userId,
                ...$this->taskAttributes($mutation['task']),
                'version' => 1,
            ]);
        } elseif (
            $task === null
            && $mutation['operation'] === 'delete'
            && $baseVersion === 0
        ) {
            return [
                'mutation_id' => $mutation['mutation_id'],
                'task_uuid' => $mutation['task_uuid'],
                'server_id' => $mutation['task_uuid'],
                'status' => 'synced',
                'version' => 0,
                'deleted' => true,
                'task' => null,
            ];
        } elseif (
            $task === null
            || $task->version !== $baseVersion
        ) {
            return $this->conflictResult($mutation, $task);
        } elseif ($mutation['operation'] === 'upsert') {
            if ($task->trashed()) {
                $task->restore();
            }
            $task->fill($this->taskAttributes($mutation['task']));
            $task->version++;
            $task->save();
        } else {
            $task->version++;
            $task->save();
            $task->delete();
        }

        $this->recordTaskChange($task);

        return [
            'mutation_id' => $mutation['mutation_id'],
            'task_uuid' => $task->id,
            'server_id' => $task->id,
            'status' => 'synced',
            'version' => $task->version,
            'deleted' => $task->trashed(),
            'task' => (new TaskResource($task))->resolve(),
        ];
    }

    /**
     * @param  array<string, mixed>  $attributes
     * @return array<string, mixed>
     */
    private function taskAttributes(array $attributes): array
    {
        return [
            'title' => $attributes['title'],
            'note' => $attributes['note'] ?? null,
            'start_datetime' => Carbon::parse($attributes['start_datetime'])->utc(),
            'end_datetime' => Carbon::parse($attributes['end_datetime'])->utc(),
            'status' => $attributes['status'],
        ];
    }

    /**
     * @param  array<string, mixed>  $mutation
     * @return array<string, mixed>
     */
    private function conflictResult(array $mutation, ?Task $task): array
    {
        return [
            'mutation_id' => $mutation['mutation_id'],
            'task_uuid' => $mutation['task_uuid'],
            'server_id' => $task?->id,
            'status' => 'conflict',
            'version' => $task?->version ?? 0,
            'deleted' => $task?->trashed() ?? false,
            'task' => $task === null ? null : (new TaskResource($task))->resolve(),
        ];
    }

    private function canonicalize(mixed $value): mixed
    {
        if (! is_array($value)) {
            return $value;
        }

        if (array_is_list($value)) {
            return array_map(fn ($item) => $this->canonicalize($item), $value);
        }

        ksort($value);

        foreach ($value as $key => $item) {
            $value[$key] = $this->canonicalize($item);
        }

        return $value;
    }

    private function recordTaskChange(Task $task): void
    {
        $sequence = TaskChangeSequence::query()
            ->whereKey(1)
            ->lockForUpdate()
            ->firstOrFail();
        $sequence->value++;
        $sequence->save();

        TaskChange::query()->create([
            'id' => $sequence->value,
            'task_uuid' => $task->id,
            'version' => $task->version,
        ]);
    }
}
