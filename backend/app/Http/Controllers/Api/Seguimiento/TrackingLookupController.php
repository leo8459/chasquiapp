<?php

namespace App\Http\Controllers\Api\Seguimiento;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\PackageLookupRequest;
use App\Services\Seguimiento\SiopTrackingEventsService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;

class TrackingLookupController extends Controller
{
    public function __invoke(PackageLookupRequest $request, SiopTrackingEventsService $trackingLookupService): JsonResponse
    {
        $payload = $trackingLookupService->findPackageByCode(
            $request->string('code')->toString(),
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
