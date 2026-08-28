<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $pgsql = config('database.connections.pgsql');

        config([
            'database.default' => 'pgsql',
            'database.connections' => [
                'pgsql' => $pgsql,
            ],
        ]);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        RateLimiter::for('mobile-login', function (Request $request): Limit {
            $email = strtolower(trim((string) $request->input('email', '')));

            return Limit::perMinute(8)->by($request->ip().'|'.$email);
        });

        RateLimiter::for('mobile-api', function (Request $request): Limit {
            $token = trim((string) $request->bearerToken());
            $key = $token !== '' ? hash('sha256', $token) : (string) $request->ip();

            return Limit::perMinute(180)->by($key);
        });

        RateLimiter::for('mobile-public', function (Request $request): Limit {
            return Limit::perMinute(60)->by((string) $request->ip());
        });
    }
}
