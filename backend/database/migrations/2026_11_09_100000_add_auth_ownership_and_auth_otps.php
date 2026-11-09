<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table) {
            $table->foreignId('user_id')->nullable()->after('id')
                ->constrained()->cascadeOnDelete();
            $table->index(['user_id', 'id']);
        });

        Schema::table('task_sync_mutations', function (Blueprint $table) {
            $table->foreignId('user_id')->nullable()->after('mutation_id')
                ->constrained()->cascadeOnDelete();
            $table->index(['user_id', 'mutation_id']);
        });

        Schema::create('auth_otps', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('purpose', 32);
            $table->string('otp_hash');
            $table->string('reset_token_hash')->nullable();
            $table->timestamp('expires_at');
            $table->timestamp('last_sent_at');
            $table->timestamp('verified_at')->nullable();
            $table->timestamp('consumed_at')->nullable();
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamps();
            $table->index(['user_id', 'purpose', 'created_at']);
        });

        $existingUsers = DB::table('users')->orderBy('id')->limit(2)->pluck('id');
        if ($existingUsers->count() === 1) {
            $userId = $existingUsers->first();
            DB::table('tasks')->whereNull('user_id')->update(['user_id' => $userId]);

            $unownedMutations = DB::table('task_sync_mutations')
                ->whereNull('user_id')
                ->get(['mutation_id', 'task_uuid']);
            foreach ($unownedMutations as $mutation) {
                $ownerId = DB::table('tasks')
                    ->where('id', $mutation->task_uuid)
                    ->value('user_id');
                if ($ownerId !== null) {
                    DB::table('task_sync_mutations')
                        ->where('mutation_id', $mutation->mutation_id)
                        ->update(['user_id' => $ownerId]);
                }
            }
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('auth_otps');

        Schema::table('task_sync_mutations', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
            $table->dropIndex(['user_id', 'mutation_id']);
            $table->dropColumn('user_id');
        });

        Schema::table('tasks', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
            $table->dropIndex(['user_id', 'id']);
            $table->dropColumn('user_id');
        });
    }
};
