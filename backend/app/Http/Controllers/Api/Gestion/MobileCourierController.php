<?php

namespace App\Http\Controllers\Api\Gestion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileCourierLookupRequest;
use App\Http\Requests\Api\Movil\MobileInventoryAssignmentStoreRequest;
use App\Services\OperacionesPostales\MobilePackageTrackingService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileCourierController extends Controller
{
    use ResolvesMobileAuthUser;

    public function index(
        Request $request,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        $allCities = strtolower(trim((string) $request->query('scope', ''))) === 'all'
            || $request->boolean('all_cities');

        $payload = $packageTrackingService->findAvailableCouriers(
            $this->mobileAuthUser($request),
            $allCities,
        );

        return MobileApiResponse::success([
            'city' => $payload['city'],
            'couriers' => $payload['couriers'],
        ]);
    }

    public function lookup(
        MobileCourierLookupRequest $request,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        $ci = $request->string('ci')->toString();
        $courier = $packageTrackingService->findCourierByCi(
            $this->mobileAuthUser($request),
            $ci,
        );

        if ($courier === null) {
            return MobileApiResponse::error(
                'No encontramos un cartero con ese CI.',
                404,
                'COURIER_NOT_FOUND',
                payload: [
                    'found' => false,
                    'ci' => $ci,
                ],
            );
        }

        return MobileApiResponse::success([
            'found' => true,
            'user' => $courier,
        ]);
    }

    public function inventoryPackages(
        Request $request,
        int $userId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        $payload = $packageTrackingService->findInventoryPackagesForCourier(
            $this->mobileAuthUser($request),
            $userId,
        );

        return MobileApiResponse::success([
            'city' => $payload['city'],
            'courier' => $payload['courier'],
            'packages' => $payload['packages'],
        ]);
    }

    public function regionalRecentAssignments(
        Request $request,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success([
            'assignments' => $packageTrackingService->findRecentRegionalAssignedPackages(
                $this->mobileAuthUser($request),
            ),
        ]);
    }

    public function assignInventoryPackage(
        MobileInventoryAssignmentStoreRequest $request,
        int $userId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        $packageIds = $request->input('package_ids');
        $normalizedPackageIds = is_array($packageIds)
            ? array_values(array_map(static fn ($value): int => (int) $value, $packageIds))
            : [];

        return MobileApiResponse::success(
            count($normalizedPackageIds) > 1
                ? $packageTrackingService->assignInventoryPackagesToCourier(
                    $this->mobileAuthUser($request),
                    $userId,
                    $request->string('package_type')->toString(),
                    $normalizedPackageIds,
                )
                : $packageTrackingService->assignInventoryPackageToCourier(
                    $this->mobileAuthUser($request),
                    $userId,
                    $request->string('package_type')->toString(),
                    (int) ($normalizedPackageIds[0] ?? $request->integer('package_id')),
                ),
        );
    }

    public function revertAssignmentToWarehouse(
        Request $request,
        int $userId,
        int $assignmentId,
        MobilePackageTrackingService $packageTrackingService,
    ): JsonResponse {
        return MobileApiResponse::success(
            $packageTrackingService->revertAssignmentToWarehouse(
                $this->mobileAuthUser($request),
                $userId,
                $assignmentId,
            ),
        );
    }
}
