<?php

namespace Tests\Feature;

use App\Models\Task;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Auth;
use Tests\TestCase;

class TaskSyncTest extends TestCase
{
    use RefreshDatabase;

    private User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create(['email_verified_at' => now()]);
        $this->actingAs($this->user, 'sanctum');
    }

    public function test_replaying_a_mutation_does_not_duplicate_a_task(): void
    {
        $mutation = $this->upsertMutation(
            '11111111-1111-4111-8111-111111111111',
            '22222222-2222-4222-8222-222222222222',
            0,
            'Plan the week',
        );

        $first = $this->postJson('/api/v1/sync', ['mutations' => [$mutation]]);
        $replay = $this->postJson('/api/v1/sync', ['mutations' => [$mutation]]);

        $first->assertOk()->assertJsonPath('data.0.status', 'synced');
        $replay->assertOk()->assertExactJson($first->json());
        $this->assertDatabaseCount('tasks', 1);
        $this->assertDatabaseCount('task_changes', 1);
        $this->assertDatabaseCount('task_sync_mutations', 1);
    }

    public function test_reusing_a_mutation_id_with_different_content_is_rejected(): void
    {
        $mutationId = '12121212-1212-4121-8121-121212121212';
        $taskUuid = '23232323-2323-4232-8232-232323232323';
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation($mutationId, $taskUuid, 0, 'First title'),
            ],
        ])->assertOk();

        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation($mutationId, $taskUuid, 0, 'Different title'),
            ],
        ])->assertJsonPath('data.0.status', 'idempotency_key_reused');

        $this->assertDatabaseHas('tasks', [
            'id' => $taskUuid,
            'title' => 'First title',
            'version' => 1,
        ]);
    }

    public function test_stale_versions_return_conflicts_without_overwriting_server_data(): void
    {
        $taskUuid = '33333333-3333-4333-8333-333333333333';
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    '44444444-4444-4444-8444-444444444444',
                    $taskUuid,
                    0,
                    'Original title',
                ),
            ],
        ])->assertOk();

        $response = $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    '55555555-5555-4555-8555-555555555555',
                    $taskUuid,
                    0,
                    'Offline title',
                ),
            ],
        ]);

        $response->assertOk()
            ->assertJsonPath('data.0.status', 'conflict')
            ->assertJsonPath('data.0.version', 1)
            ->assertJsonPath('data.0.task.title', 'Original title');
        $this->assertDatabaseHas('tasks', [
            'id' => $taskUuid,
            'title' => 'Original title',
            'version' => 1,
        ]);
    }

    public function test_incremental_pull_includes_a_deleted_task_tombstone(): void
    {
        $taskUuid = '66666666-6666-4666-8666-666666666666';
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    '77777777-7777-4777-8777-777777777777',
                    $taskUuid,
                    0,
                    'Delete me',
                ),
            ],
        ])->assertOk();

        $this->postJson('/api/v1/sync', [
            'mutations' => [[
                'mutation_id' => '88888888-8888-4888-8888-888888888888',
                'task_uuid' => $taskUuid,
                'operation' => 'delete',
                'base_version' => 1,
            ]],
        ])->assertJsonPath('data.0.status', 'synced');

        $response = $this->getJson('/api/v1/tasks?cursor=0');
        $response->assertOk()
            ->assertJsonPath('data.0.task_uuid', $taskUuid)
            ->assertJsonPath('data.0.version', 2)
            ->assertJsonPath('meta.next_cursor', 2);
        $this->assertDatabaseHas('tasks', ['id' => $taskUuid]);
    }

    public function test_invalid_mutation_is_reported_without_persisting(): void
    {
        $response = $this->postJson('/api/v1/sync', [
            'mutations' => [[
                'mutation_id' => '99999999-9999-4999-8999-999999999999',
                'task_uuid' => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                'operation' => 'upsert',
                'base_version' => 0,
                'task' => [
                    'title' => '',
                    'status' => 'pending',
                    'start_datetime' => '2026-11-05T10:00:00',
                    'end_datetime' => '2026-11-05T11:00:00Z',
                ],
            ]],
        ]);

        $response->assertOk()->assertJsonPath('data.0.status', 'validation_error');
        $this->assertDatabaseCount('tasks', 0);
    }

    public function test_only_pending_and_done_task_statuses_are_accepted(): void
    {
        $mutation = $this->upsertMutation(
            '98989898-9898-4989-8989-989898989898',
            '97979797-9797-4979-8979-979797979797',
            0,
            'Task with invalid status',
        );
        $mutation['task']['status'] = 'in_progress';

        $this->postJson('/api/v1/sync', ['mutations' => [$mutation]])
            ->assertOk()
            ->assertJsonPath('data.0.status', 'validation_error');
        $this->assertDatabaseCount('tasks', 0);
    }

    public function test_local_resolution_can_restore_a_server_deleted_task(): void
    {
        $taskUuid = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
                    $taskUuid,
                    0,
                    'Keep this task',
                ),
            ],
        ])->assertOk();
        $this->postJson('/api/v1/sync', [
            'mutations' => [[
                'mutation_id' => 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
                'task_uuid' => $taskUuid,
                'operation' => 'delete',
                'base_version' => 1,
            ]],
        ])->assertJsonPath('data.0.version', 2);

        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
                    $taskUuid,
                    2,
                    'Restore local copy',
                ),
            ],
        ])->assertJsonPath('data.0.status', 'synced')
            ->assertJsonPath('data.0.version', 3);

        $this->assertDatabaseHas('tasks', [
            'id' => $taskUuid,
            'title' => 'Restore local copy',
            'version' => 3,
            'deleted_at' => null,
        ]);
    }

    public function test_task_sync_is_protected_and_shared_between_authenticated_users(): void
    {
        Auth::forgetGuards();
        $this->postJson('/api/v1/sync', ['mutations' => []])->assertUnauthorized();

        $this->actingAs($this->user, 'sanctum');
        $taskUuid = 'abababab-abab-4bab-8bab-abababababab';
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
                    $taskUuid,
                    0,
                    'Private task',
                ),
            ],
        ])->assertOk()->assertJsonPath('data.0.status', 'synced');

        $otherUser = User::factory()->create(['email_verified_at' => now()]);
        $this->actingAs($otherUser, 'sanctum');
        $this->getJson('/api/v1/tasks?cursor=0')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.created_by_user_id', $this->user->id)
            ->assertJsonPath('data.0.updated_by_user_id', $this->user->id);
        $this->postJson('/api/v1/sync', [
            'mutations' => [
                $this->upsertMutation(
                    'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
                    $taskUuid,
                    0,
                    'Private task',
                ),
            ],
        ])->assertOk()
            ->assertJsonPath('data.0.status', 'idempotency_key_reused')
            ->assertJsonMissingPath('data.0.task');
        $sharedUpdate = $this->upsertMutation(
            'dededede-dede-4ede-8ede-dededededede',
            $taskUuid,
            1,
            'Updated by a shared user',
        );
        $sharedUpdate['task']['user_id'] = 999999;
        $sharedUpdate['task']['updated_by_user_id'] = 999999;
        $this->postJson('/api/v1/sync', ['mutations' => [$sharedUpdate]])
            ->assertOk()
            ->assertJsonPath('data.0.status', 'synced')
            ->assertJsonPath('data.0.task.created_by_user_id', $this->user->id)
            ->assertJsonPath('data.0.task.updated_by_user_id', $otherUser->id);
        $this->getJson('/api/v1/tasks?cursor=1')
            ->assertOk()
            ->assertJsonPath('data.0.title', 'Updated by a shared user')
            ->assertJsonPath('data.0.updated_by_user_id', $otherUser->id)
            ->assertJsonPath('meta.next_cursor', 2);

        $this->postJson('/api/v1/sync', [
            'mutations' => [[
                'mutation_id' => 'efefefef-efef-4fef-8fef-efefefefefef',
                'task_uuid' => $taskUuid,
                'operation' => 'delete',
                'base_version' => 2,
            ]],
        ])->assertOk()
            ->assertJsonPath('data.0.status', 'synced')
            ->assertJsonPath('data.0.task.updated_by_user_id', $otherUser->id);
        $this->getJson('/api/v1/tasks?cursor=2')
            ->assertOk()
            ->assertJsonPath('data.0.task_uuid', $taskUuid)
            ->assertJsonPath('data.0.deleted_at', fn ($value) => $value !== null)
            ->assertJsonPath('meta.next_cursor', 3);

        $this->assertDatabaseHas('tasks', [
            'id' => $taskUuid,
            'user_id' => $this->user->id,
            'updated_by_user_id' => $otherUser->id,
            'title' => 'Updated by a shared user',
        ]);
        $this->assertTrue(Task::withTrashed()->findOrFail($taskUuid)->trashed());
    }

    /**
     * @return array<string, mixed>
     */
    private function upsertMutation(
        string $mutationId,
        string $taskUuid,
        int $baseVersion,
        string $title,
    ): array {
        return [
            'mutation_id' => $mutationId,
            'task_uuid' => $taskUuid,
            'operation' => 'upsert',
            'base_version' => $baseVersion,
            'task' => [
                'title' => $title,
                'note' => null,
                'start_datetime' => '2026-11-05T09:00:00.000Z',
                'end_datetime' => '2026-11-05T10:00:00.000Z',
                'status' => 'pending',
            ],
        ];
    }
}
