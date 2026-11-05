<?php

use App\Models\TaskChangeSequence;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('task_change_sequence', function (Blueprint $table) {
            $table->unsignedTinyInteger('id')->primary();
            $table->unsignedBigInteger('value')->default(0);
        });

        TaskChangeSequence::query()->create(['id' => 1, 'value' => 0]);
    }

    public function down(): void
    {
        Schema::dropIfExists('task_change_sequence');
    }
};
