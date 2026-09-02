<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CourierNotificationsTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_courier_notifications.pending_url' => 'https://siop.example.test/notifications',
            'services.siop_courier_notifications.token' => 'notification-integration-token',
            'services.siop_courier_notifications.verify_ssl' => true,
            'services.siop_courier_packages.assigned_url' => 'https://siop.example.test/assigned',
            'services.siop_courier_packages.assigned_token' => 'assigned-integration-token',
            'services.siop_courier_packages.verify_ssl' => true,
        ]);
    }

    public function test_courier_can_get_normalized_pending_notifications_with_dual_authentication(): void
    {
        Http::fake([
            'https://siop.example.test/notifications' => Http::response([
                'data' => [[
                    'id_notificacion' => 91,
                    'titulo' => 'Paquete asignado',
                    'mensaje' => 'Tienes un paquete nuevo.',
                    'fecha_creacion' => '2026-09-01T13:10:00-04:00',
                    'paquete' => ['codigo' => 'EE123456789BO'],
                ]],
            ]),
        ]);

        $mobileToken = app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Cartero de prueba',
            'email' => 'cartero@correos.gob.bo',
            'roles' => ['cartero'],
        ], 'siop-user-token');

        $this->withToken($mobileToken)
            ->getJson('/api/mobile/courier/pending-notifications')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('notifications.0.id', '91')
            ->assertJsonPath('notifications.0.package_code', 'EE123456789BO')
            ->assertJsonPath('notifications.0.title', 'Paquete asignado');

        Http::assertSent(fn (Request $request): bool =>
            $request->url() === 'https://siop.example.test/notifications'
            && $request->hasHeader('Authorization', 'Bearer siop-user-token')
            && $request->hasHeader('X-API-Token', 'notification-integration-token')
        );
    }

    public function test_assigned_packages_are_used_when_bolipost_has_no_pending_notifications(): void
    {
        Http::fake([
            'https://siop.example.test/notifications' => Http::response(['data' => []]),
            'https://siop.example.test/assigned*' => Http::response([
                'data' => [[
                    'id_asignacion' => 44,
                    'fecha_asignacion' => '2026-09-01T10:15:00-04:00',
                    'paquete' => [
                        'id' => 500,
                        'codigo' => 'EE123456789BO',
                        'tipo' => 'ems',
                    ],
                ]],
                'paginacion' => ['pagina_actual' => 1, 'ultima_pagina' => 1],
            ]),
        ]);

        $mobileToken = app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Cartero de prueba',
            'email' => 'cartero@correos.gob.bo',
            'roles' => ['cartero'],
        ], 'siop-user-token');

        $this->withToken($mobileToken)
            ->getJson('/api/mobile/courier/pending-notifications')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('notifications.0.id', 'assigned-44')
            ->assertJsonPath('notifications.0.package_code', 'EE123456789BO')
            ->assertJsonPath('notifications.0.title', 'Paquete asignado');
    }
}
