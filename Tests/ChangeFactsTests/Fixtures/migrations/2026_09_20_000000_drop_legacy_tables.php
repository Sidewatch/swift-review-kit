<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::dropIfExists('legacy_profiles');
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('bio');
            $table->string('age', 8)->change();
        });
        DB::statement("TRUNCATE TABLE analytics_events");
    }

    public function down(): void
    {
    }
};
