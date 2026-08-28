<?php

namespace App\Http\Controllers\Api\Clasificacion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileScannerStoreRequest;
use App\Services\Clasificacion\MobileScannerService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileScannerController extends Controller
{
    use ResolvesMobileAuthUser;

    public function ventanillas(
        Request $request,
        MobileScannerService $scannerService,
    ): JsonResponse {
        return MobileApiResponse::success([
            'ventanillas' => $scannerService->getVentanillas(
                $this->mobileAuthUser($request),
            ),
        ]);
    }

    public function store(
        MobileScannerStoreRequest $request,
        MobileScannerService $scannerService,
    ): JsonResponse {
        $scannerService->saveScan(
            $this->mobileAuthUser($request),
            $request->validated(),
        );

        return MobileApiResponse::success(
            status: 201,
            message: 'Paquete registrado correctamente.',
        );
    }
}
