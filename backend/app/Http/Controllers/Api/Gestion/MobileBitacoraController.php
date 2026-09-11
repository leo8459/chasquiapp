<?php

namespace App\Http\Controllers\Api\Gestion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileBitacoraStoreRequest;
use App\Services\Gestion\SiopBitacoraService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileBitacoraController extends Controller
{
    use ResolvesMobileAuthUser;

    public function __invoke(
        Request $request,
        SiopBitacoraService $bitacoraService,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($bitacoraService->list(
            max(1, $request->integer('page', 1)),
            max(1, min(100, $request->integer('per_page', 20))),
        ));
    }

    public function store(
        MobileBitacoraStoreRequest $request,
        SiopBitacoraService $bitacoraService,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success(
            $bitacoraService->create(
                $request->safe()->except('odometro_photo'),
                $request->file('odometro_photo'),
            ),
            201,
        );
    }

    public function vehicles(
        Request $request,
        SiopBitacoraService $bitacoraService,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($bitacoraService->vehicles());
    }

    public function drivers(
        Request $request,
        SiopBitacoraService $bitacoraService,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($bitacoraService->drivers());
    }
}
