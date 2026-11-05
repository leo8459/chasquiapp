<?php

namespace App\Http\Middleware;

use App\Services\MobileVersionPolicy;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RequireMobileAppVersion
{
    public function handle(Request $request, Closure $next): Response
    {
        $metadata = app(MobileVersionPolicy::class)->metadata(
            trim((string) $request->header('X-App-Version', '')),
        );

        if ($metadata['update_required']) {
            return response()->json([
                'message' => 'Actualiza ChasquiApp para continuar.',
                'error_code' => 'APP_UPDATE_REQUIRED',
                ...$metadata,
            ], 426)->header('Cache-Control', 'no-store');
        }

        return $next($request);
    }
}
