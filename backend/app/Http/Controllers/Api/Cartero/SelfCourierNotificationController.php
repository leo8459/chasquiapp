<?php

namespace App\Http\Controllers\Api\Cartero;

use App\Http\Controllers\Controller;
use App\Services\Cartero\SiopCourierNotificationsService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SelfCourierNotificationController extends Controller
{
    public function __invoke(Request $request, SiopCourierNotificationsService $service): JsonResponse
    {
        return MobileApiResponse::success(
            $service->pending($request->bearerToken()),
        );
    }
}
