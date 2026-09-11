<?php

namespace App\Http\Controllers\Api\Gestion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileMantenimientoStoreRequest;
use App\Services\Gestion\SiopMantenimientoService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileMantenimientoController extends Controller
{
    use ResolvesMobileAuthUser;

    public function index(Request $request, SiopMantenimientoService $service): JsonResponse
    {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($service->list(
            max(1, $request->integer('page', 1)),
            max(1, min(100, $request->integer('per_page', 20))),
        ));
    }

    public function options(Request $request, SiopMantenimientoService $service): JsonResponse
    {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($service->options());
    }

    public function store(
        MobileMantenimientoStoreRequest $request,
        SiopMantenimientoService $service,
    ): JsonResponse {
        $this->mobileAuthUser($request);

        return MobileApiResponse::success($service->create($request->validated()), 201);
    }
}
