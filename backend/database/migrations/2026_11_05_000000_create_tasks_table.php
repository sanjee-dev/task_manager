<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tasks', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('title', 255);
            $table->text('note')->nullable();
            $table->dateTime('start_datetime', precision: 6);
            $table->dateTime('end_datetime', precision: 6);
            $table->string('status', 20)->default('pending');
            $table->unsignedInteger('version')->default(1);
            $table->timestamps(6);
            $table->softDeletes('deleted_at', precision: 6);
            $table->index(['updated_at', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tasks');
    }
};
