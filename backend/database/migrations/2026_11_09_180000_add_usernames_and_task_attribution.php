<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('username', 50)->nullable()->unique()->after('id');
        });

        DB::table('users')->orderBy('id')->each(function (object $user): void {
            DB::table('users')
                ->where('id', $user->id)
                ->update(['username' => 'user_'.$user->id]);
        });

        Schema::table('tasks', function (Blueprint $table) {
            $table->foreignId('updated_by_user_id')
                ->nullable()
                ->after('user_id')
                ->constrained('users')
                ->nullOnDelete();
            $table->index(['updated_by_user_id', 'id']);
        });

        DB::table('tasks')
            ->whereNotNull('user_id')
            ->update(['updated_by_user_id' => DB::raw('user_id')]);

        $changeSequence = (int) DB::table('task_change_sequence')
            ->where('id', 1)
            ->value('value');
        $changeSequence = max(
            $changeSequence,
            (int) DB::table('task_changes')->max('id'),
        );

        DB::table('tasks')->orderBy('id')->each(function (object $task) use (&$changeSequence): void {
            $hasHistory = DB::table('task_changes')
                ->where('task_uuid', $task->id)
                ->exists();
            if ($hasHistory) {
                return;
            }

            DB::table('task_changes')->insert([
                'id' => ++$changeSequence,
                'task_uuid' => $task->id,
                'version' => $task->version,
                'created_at' => now(),
            ]);
        });

        DB::table('task_change_sequence')
            ->where('id', 1)
            ->update(['value' => $changeSequence]);
    }

    public function down(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->dropForeign(['updated_by_user_id']);
            $table->dropIndex(['updated_by_user_id', 'id']);
            $table->dropColumn('updated_by_user_id');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropUnique(['username']);
            $table->dropColumn('username');
        });
    }
};
