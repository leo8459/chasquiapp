<?php

namespace App\Services\Autenticacion;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

class MobileApiTokenService
{
    private const CACHE_PREFIX = 'mobile_api_token:';

    public function issue(array $user, ?string $siopAccessToken = null): string
    {
        $token = Str::random(80);

        Cache::forever(
            $this->cacheKey($token),
            [
                'id' => (int) ($user['id'] ?? 0),
                'email' => (string) ($user['email'] ?? ''),
                'user' => $user,
                'siop_access_token' => trim((string) $siopAccessToken),
                'issued_at' => now()->toIso8601String(),
            ],
        );

        return $token;
    }

    public function getPayload(?string $token): ?array
    {
        $normalizedToken = trim((string) $token);
        if ($normalizedToken === '') {
            return null;
        }

        $cacheKey = $this->cacheKey($normalizedToken);
        $payload = Cache::get($cacheKey);

        if (is_array($payload)) {
            // Promote tokens created by older releases (30-day TTL) so an
            // authenticated mobile session only ends through explicit logout.
            Cache::forever($cacheKey, $payload);
        }

        return is_array($payload) ? $payload : null;
    }

    public function forget(?string $token): void
    {
        $normalizedToken = trim((string) $token);
        if ($normalizedToken === '') {
            return;
        }

        Cache::forget($this->cacheKey($normalizedToken));
    }

    private function cacheKey(string $token): string
    {
        return self::CACHE_PREFIX.hash('sha256', $token);
    }
}
