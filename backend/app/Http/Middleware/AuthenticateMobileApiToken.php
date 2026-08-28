<?php

namespace App\Http\Middleware;

use App\Services\Autenticacion\MobileAuthService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateMobileApiToken
{
    public function handle(Request $request, Closure $next): Response
    {
        $authService = app(MobileAuthService::class);

        $request->attributes->set(
            'mobile_auth_user',
            $authService->authenticateRequest($request),
        );

        return $next($request);
    }
}
