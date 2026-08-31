<?php

namespace App\Http\Controllers\Api\Autenticacion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileAuthLoginRequest;
use App\Services\Autenticacion\MobileAuthService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileAuthController extends Controller
{
    use ResolvesMobileAuthUser;

    public function login(MobileAuthLoginRequest $request, MobileAuthService $authService): JsonResponse
    {
        return MobileApiResponse::success(
            $authService->signIn(
                $request->string('alias')->toString(),
                $request->string('password')->toString(),
            ),
        );
    }

    public function me(Request $request): JsonResponse
    {
        return MobileApiResponse::success([
            'user' => $this->mobileAuthUser($request),
        ]);
    }

    public function logout(Request $request, MobileAuthService $authService): JsonResponse
    {
        $authService->logout($request->bearerToken());

        return MobileApiResponse::success(
            message: 'Sesion cerrada correctamente.',
        );
    }
}
