<?php

namespace App\Http\Controllers\Api\Cartero;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\CourierLocationHeartbeatRequest;
use App\Services\Cartero\SiopCourierLocationService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SelfCourierLocationController extends Controller
{
    public function index(Request $request, SiopCourierLocationService $service): JsonResponse
    {
        return MobileApiResponse::success($service->latest());
    }

    public function store(
        CourierLocationHeartbeatRequest $request,
        SiopCourierLocationService $service,
    ): JsonResponse {
        return MobileApiResponse::success(
            $service->publish($request->bearerToken(), $request->validated()),
        );
    }
}
