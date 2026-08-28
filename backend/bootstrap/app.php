<?php

use App\Exceptions\MobileApiException;
use App\Http\Middleware\AuthenticateMobileApiToken;
use App\Support\MobileApi\MobileApiResponse;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'mobile.api.auth' => AuthenticateMobileApiToken::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->dontReport([
            MobileApiException::class,
        ]);

        $exceptions->render(function (MobileApiException $exception, Request $request) {
            if (! MobileApiResponse::handles($request)) {
                return null;
            }

            $message = $exception->getMessage();
            if ($exception->status() >= 500) {
                Log::error('Error operativo en la API movil.', [
                    'error_code' => $exception->errorCode(),
                    'exception' => $exception,
                ]);
                $message = 'No pudimos completar esta acción en este momento. Intenta nuevamente.';
            }

            return MobileApiResponse::error(
                $message,
                $exception->status(),
                $exception->errorCode(),
            );
        });

        $exceptions->render(function (ValidationException $exception, Request $request) {
            if (! MobileApiResponse::handles($request)) {
                return null;
            }

            return MobileApiResponse::validation(
                'Revisa los datos enviados e intenta nuevamente.',
                $exception->errors(),
            );
        });

        $exceptions->render(function (Throwable $exception, Request $request) {
            if (! MobileApiResponse::handles($request) || $exception instanceof HttpExceptionInterface) {
                return null;
            }

            return MobileApiResponse::error(
                'No se pudo completar la solicitud en este momento.',
                503,
                'MOBILE_API_UNAVAILABLE',
            );
        });
    })->create();
