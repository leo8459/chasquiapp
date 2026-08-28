<?php

namespace App\Http\Controllers\Api\Seguimiento;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\TrackingEventsRequest;
use App\Services\Seguimiento\SiopTrackingEventsService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;

class TrackingEventsController extends Controller
{
    public function __invoke(
        TrackingEventsRequest $request,
        SiopTrackingEventsService $trackingEventsService,
    ): JsonResponse {
        return MobileApiResponse::success(
            $trackingEventsService->findByCode(
                $request->string('code')->toString(),
                $request->string('table')->toString() ?: null,
                $request->integer('limit', 30),
            ),
        );
    }
}
