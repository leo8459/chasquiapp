<?php

namespace App\Support\MobileApi;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class MobileApiResponse
{
    public static function success(
        array $payload = [],
        int $status = 200,
        ?string $message = null,
    ): JsonResponse {
        $response = array_merge(['ok' => true], $payload);

        if ($message !== null && trim($message) !== '' && ! array_key_exists('message', $response)) {
            $response['message'] = $message;
        }

        $response['timestamp'] = now()->toIso8601String();

        return response()->json($response, $status);
    }

    public static function error(
        string $message,
        int $status,
        ?string $errorCode = null,
        array $errors = [],
        array $payload = [],
    ): JsonResponse {
        $response = array_merge([
            'ok' => false,
            'message' => $message,
        ], $payload);

        if ($errorCode !== null && trim($errorCode) !== '') {
            $response['error_code'] = $errorCode;
        }

        if ($errors !== []) {
            $response['errors'] = $errors;
        }

        $response['timestamp'] = now()->toIso8601String();

        return response()->json($response, $status);
    }

    public static function validation(string $message, array $errors): JsonResponse
    {
        return self::error($message, 422, 'VALIDATION_ERROR', $errors);
    }

    public static function handles(Request $request): bool
    {
        return $request->is('api/mobile')
            || $request->is('api/mobile/*')
            || $request->is('api/tracking/package')
            || $request->is('api/tracking/events');
    }
}
