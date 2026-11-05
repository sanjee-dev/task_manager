<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('task_changes', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->foreignUuid('task_uuid')->constrained('tasks')->cascadeOnDelete();
            $table->unsignedInteger('version');
            $table->timestamp('created_at', 6)->useCurrent();
            $table->index(['task_uuid', 'version']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_changes');
    }
};
