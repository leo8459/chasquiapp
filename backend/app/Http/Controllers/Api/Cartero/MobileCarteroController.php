<?php

namespace App\Http\Controllers\Api\Cartero;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileAssignmentStatusUpdateRequest;
use App\Services\OperacionesPostales\MobilePackageTrackingService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileCarteroController extends Controller
{
    use ResolvesMobileAuthUser;

    public function assignments(
        Request $request,
        int $userId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success([
            'assignments' => $packageTrackingService->findAssignmentsForUser(
                $this->mobileAuthUser($request),
                $userId,
            ),
        ]);
    }

    public function updateStatus(
        MobileAssignmentStatusUpdateRequest $request,
        int $assignmentId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success(
            $packageTrackingService->updateAssignmentStatus(
                $this->mobileAuthUser($request),
                $assignmentId,
                (int) $request->integer('user_id'),
                $request->string('status')->toString(),
            ),
        );
    }
}
