<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\MobileVersionPolicy;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileAppVersionController extends Controller
{
    public function __invoke(Request $request, MobileVersionPolicy $policy): JsonResponse
    {
        return response()->json($policy->metadata(
            trim((string) $request->header('X-App-Version', '')),
        ))->header('Cache-Control', 'no-store');
    }
}
