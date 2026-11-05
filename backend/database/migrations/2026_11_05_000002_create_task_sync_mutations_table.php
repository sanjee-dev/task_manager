<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('task_sync_mutations', function (Blueprint $table) {
            $table->uuid('mutation_id')->primary();
            $table->uuid('task_uuid')->index();
            $table->char('request_hash', 64);
            $table->json('response');
            $table->timestamp('created_at', 6)->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_sync_mutations');
    }
};
