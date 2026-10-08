<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('call_histories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('peer_user_id')->constrained('users')->cascadeOnDelete();
            $table->uuid('call_uuid')->nullable()->index();
            $table->string('direction', 10);
            $table->string('status', 20)->index();
            $table->timestamp('initiated_at');
            $table->timestamp('accepted_at')->nullable();
            $table->timestamp('connected_at')->nullable();
            $table->timestamp('ended_at')->nullable();
            $table->unsignedInteger('duration_seconds')->default(0);
            $table->timestamps();

            $table->index(['user_id', 'initiated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('call_histories');
    }
};
