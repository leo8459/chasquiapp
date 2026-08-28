<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('cartero') || Schema::hasColumn('cartero', 'firma')) {
            return;
        }

        Schema::table('cartero', function (Blueprint $table): void {
            $table->text('firma')->nullable();
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('cartero') || ! Schema::hasColumn('cartero', 'firma')) {
            return;
        }

        Schema::table('cartero', function (Blueprint $table): void {
            $table->dropColumn('firma');
        });
    }
};
