<?php

namespace App\Http\Controllers\Api\Gestion;

use App\Http\Controllers\Api\Concerns\ResolvesMobileAuthUser;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\Movil\MobileTransportInvoiceStoreRequest;
use App\Services\Gestion\SiopTransportInvoiceService;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Http\JsonResponse;

class MobileTransportInvoiceController extends Controller
{
    use ResolvesMobileAuthUser;

    public function store(
        MobileTransportInvoiceStoreRequest $request,
        SiopTransportInvoiceService $service,
    ): JsonResponse {
        $authUser = $this->mobileAuthUser($request);
        $data = $request->safe()->except('imagen_factura');
        $data['user_id'] = (int) $authUser['id'];

        return MobileApiResponse::success(
            $service->create(
                $data,
                $request->file('imagen_factura'),
            ),
            201,
        );
    }
}
