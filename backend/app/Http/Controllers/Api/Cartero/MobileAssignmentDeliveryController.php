<?php

namespace App\Http\Controllers\Api\Cartero;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileAssignmentDeliveryStoreRequest;
use App\Http\Requests\Api\Movil\MobileAssignmentDevolutionStoreRequest;
use App\Services\OperacionesPostales\MobilePackageTrackingService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;

class MobileAssignmentDeliveryController extends Controller
{
    use ResolvesMobileAuthUser;

    public function store(
        MobileAssignmentDeliveryStoreRequest $request,
        int $assignmentId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success(
            $packageTrackingService->confirmDelivered(
                $this->mobileAuthUser($request),
                $assignmentId,
                (int) $request->integer('user_id'),
                $request->string('received_by')->toString(),
                $request->file('delivery_photo'),
                $request->file('delivery_signature'),
            ),
        );
    }

    public function storeDevolution(
        MobileAssignmentDevolutionStoreRequest $request,
        int $assignmentId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success(
            $packageTrackingService->registerDevolutionAttempt(
                $this->mobileAuthUser($request),
                $assignmentId,
                (int) $request->integer('user_id'),
                $request->string('description')->toString(),
                $request->file('delivery_attempt_photo'),
            ),
        );
    }
}
