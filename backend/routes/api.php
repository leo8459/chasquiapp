<?php

use App\Http\Controllers\Api\Autenticacion\MobileAuthController;
use App\Http\Controllers\Api\Cartero\MobileAssignmentDeliveryController;
use App\Http\Controllers\Api\Cartero\MobileCarteroController;
use App\Http\Controllers\Api\Cartero\SelfPackageAssignmentController;
use App\Http\Controllers\Api\Clasificacion\MobileScannerController;
use App\Http\Controllers\Api\Gestion\MobileCourierController;
use App\Http\Controllers\Api\Seguimiento\MobileTrackingController;
use App\Http\Controllers\Api\Seguimiento\TrackingEventsController;
use App\Http\Controllers\Api\Seguimiento\TrackingLookupController;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    return response()->json([
        'ok' => true,
        'service' => 'backend',
    ]);
});

Route::match(['GET', 'POST'], '/tracking/package', TrackingLookupController::class)
    ->middleware('throttle:mobile-public');
Route::match(['GET', 'POST'], '/tracking/events', TrackingEventsController::class)
    ->middleware('throttle:mobile-public');

Route::prefix('mobile')->as('mobile.')->group(function (): void {
    Route::post('/auth/login', [MobileAuthController::class, 'login'])
        ->middleware('throttle:mobile-login')
        ->name('auth.login');

    Route::middleware(['mobile.api.auth', 'throttle:mobile-api'])->group(function (): void {
        Route::get('/auth/me', [MobileAuthController::class, 'me'])->name('auth.me');
        Route::post('/auth/logout', [MobileAuthController::class, 'logout'])->name('auth.logout');

        Route::match(['GET', 'POST'], '/tracking/package', MobileTrackingController::class)
            ->name('tracking.package');
        Route::match(['GET', 'POST'], '/tracking/events', TrackingEventsController::class)
            ->name('tracking.events');
        Route::get('/couriers', [MobileCourierController::class, 'index'])->name('couriers.index');
        Route::get('/couriers/lookup', [MobileCourierController::class, 'lookup'])->name('couriers.lookup');
        Route::get('/couriers/assignments/recent', [MobileCourierController::class, 'regionalRecentAssignments'])
            ->name('couriers.assignments.regional-recent');
        Route::get('/couriers/{userId}/assignments', [MobileCarteroController::class, 'assignments'])
            ->whereNumber('userId')
            ->name('couriers.assignments');
        Route::get('/courier/assigned-packages', [SelfPackageAssignmentController::class, 'index'])
            ->name('courier.assigned-packages');
        Route::post('/courier/assign-packages', [SelfPackageAssignmentController::class, 'store'])
            ->name('courier.assign-packages');
        Route::post('/courier/deliver-package', [SelfPackageAssignmentController::class, 'deliver'])
            ->name('courier.deliver-package');
        Route::post('/couriers/{userId}/assignments/{assignmentId}/revert-to-warehouse', [MobileCourierController::class, 'revertAssignmentToWarehouse'])
            ->whereNumber('userId')
            ->whereNumber('assignmentId')
            ->name('couriers.assignments.revert-to-warehouse');
        Route::get('/couriers/{userId}/inventory-packages', [MobileCourierController::class, 'inventoryPackages'])
            ->whereNumber('userId')
            ->name('couriers.inventory-packages');
        Route::post('/couriers/{userId}/inventory-packages/assign', [MobileCourierController::class, 'assignInventoryPackage'])
            ->whereNumber('userId')
            ->name('couriers.inventory-packages.assign');
        Route::post('/assignments/{assignmentId}/status', [MobileCarteroController::class, 'updateStatus'])
            ->whereNumber('assignmentId')
            ->name('assignments.status');
        Route::post('/assignments/{assignmentId}/deliver', [MobileAssignmentDeliveryController::class, 'store'])
            ->whereNumber('assignmentId')
            ->name('assignments.deliver');
        Route::post('/assignments/{assignmentId}/devolution', [MobileAssignmentDeliveryController::class, 'storeDevolution'])
            ->whereNumber('assignmentId')
            ->name('assignments.devolution');
        Route::get('/scanner/ventanillas', [MobileScannerController::class, 'ventanillas'])->name('scanner.ventanillas');
        Route::post('/scanner/scans', [MobileScannerController::class, 'store'])->name('scanner.store');
    });
});
