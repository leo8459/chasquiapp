<?php

namespace App\Services\Autenticacion;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

class MobileApiTokenService
{
    private const CACHE_PREFIX = 'mobile_api_token:';

    private const TTL_DAYS = 30;

    public function issue(array $user, ?string $siopAccessToken = null): string
    {
        $token = Str::random(80);

        Cache::put(
            $this->cacheKey($token),
            [
                'id' => (int) ($user['id'] ?? 0),
                'email' => (string) ($user['email'] ?? ''),
                'user' => $user,
                'siop_access_token' => trim((string) $siopAccessToken),
                'issued_at' => now()->toIso8601String(),
            ],
            now()->addDays(self::TTL_DAYS),
        );

        return $token;
    }

    public function getPayload(?string $token): ?array
    {
        $normalizedToken = trim((string) $token);
        if ($normalizedToken === '') {
            return null;
        }

        $payload = Cache::get($this->cacheKey($normalizedToken));

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
