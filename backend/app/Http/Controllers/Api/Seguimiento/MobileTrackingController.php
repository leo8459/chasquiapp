<?php

namespace App\Http\Controllers\Api\Seguimiento;

use App\Exceptions\MobileApiException;
use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\PackageLookupRequest;
use App\Services\Autenticacion\MobileAuthService;
use App\Services\Seguimiento\TrackingLookupService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;

class MobileTrackingController extends Controller
{
    use ResolvesMobileAuthUser;

    public function __invoke(
        PackageLookupRequest $request,
        MobileAuthService $authService,
        TrackingLookupService $trackingLookupService,
    ): JsonResponse {
        $authUser = $this->mobileAuthUser($request);

        if (! $authService->canSearchPackages($authUser)) {
            throw new MobileApiException(
                'No tienes permisos para buscar paquetes.',
                403,
                'FORBIDDEN_PACKAGE_LOOKUP',
            );
        }

        $payload = $trackingLookupService->findByCode(
            $request->string('code')->toString(),
            $authService->canManageOtherCouriers($authUser),
        );

        if (($payload['found'] ?? false) !== true) {
            return MobileApiResponse::error(
                'No encontramos el paquete solicitado.',
                404,
                'PACKAGE_NOT_FOUND',
                payload: $payload,
            );
        }

        return MobileApiResponse::success($payload);
    }
}
