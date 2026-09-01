<?php

namespace App\Http\Controllers\Api\Cartero;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\SelfPackageAssignmentRequest;
use App\Http\Requests\Api\Movil\SelfPackageDeliveryRequest;
use App\Services\Cartero\SiopCourierPackagesService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SelfPackageAssignmentController extends Controller
{
    public function index(Request $request, SiopCourierPackagesService $service): JsonResponse
    {
        return MobileApiResponse::success(
            $service->assignedPackages($request->bearerToken()),
        );
    }

    public function store(
        SelfPackageAssignmentRequest $request,
        SiopCourierPackagesService $service,
    ): JsonResponse {
        return MobileApiResponse::success(
            $service->assignPackages(
                $request->bearerToken(),
                $request->array('codes'),
            ),
        );
    }

    public function deliver(
        SelfPackageDeliveryRequest $request,
        SiopCourierPackagesService $service,
    ): JsonResponse {
        return MobileApiResponse::success(
            $service->deliverPackage(
                $request->bearerToken(),
                $request->string('code')->toString(),
                $request->string('description')->toString(),
                $request->string('received_by')->toString(),
                $request->date('delivered_at'),
                $request->file('delivery_photo'),
            ),
        );
    }
}
