<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CourierPackagesTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_courier_packages.assigned_url' => 'https://siop.example.test/assigned',
            'services.siop_courier_packages.assigned_token' => 'assigned-integration-token',
            'services.siop_courier_packages.assign_url' => 'https://siop.example.test/assign',
            'services.siop_courier_packages.assign_token' => 'assign-integration-token',
            'services.siop_courier_packages.verify_ssl' => true,
            'services.siop_tracking_events.url' => 'https://siop.example.test/events',
            'services.siop_tracking_events.token' => 'events-integration-token',
            'services.siop_tracking_events.verify_ssl' => true,
        ]);
    }

    public function test_courier_can_list_all_assigned_packages_with_dual_authentication(): void
    {
        Http::fake([
            'https://siop.example.test/assigned*' => Http::response([
                'data' => [[
                    'id_asignacion' => 44,
                    'fecha_asignacion' => '2026-08-31T10:15:00-04:00',
                    'estado' => ['id' => 2, 'nombre' => 'ASIGNADO'],
                    'destinatario' => 'DESTINATARIO DE PRUEBA',
                    'telefono' => '70000000',
                    'zona' => 'AVENIDA DE PRUEBA 123',
                    'paquete' => [
                        'id' => 500,
                        'codigo' => 'EE123456789BO',
                        'tipo' => 'ems',
                    ],
                ], [
                    'id' => 701,
                    'tipo_paquete' => 'CONTRATO',
                    'codigo' => 'C0001A89843BO',
                    'destinatario' => 'DESTINATARIO CONTRATO',
                    'telefono' => '71111111',
                    'zona' => 'CALLE CONTRATO 456',
                    'estado' => 'CARTERO',
                ]],
                'paginacion' => [
                    'pagina_actual' => 1,
                    'ultima_pagina' => 1,
                ],
            ]),
        ]);

        $mobileToken = $this->issueMobileToken();

        $this->withToken($mobileToken)
            ->getJson('/api/mobile/courier/assigned-packages')
            ->assertOk()
            ->assertJsonPath('total', 2)
            ->assertJsonPath('assignments.0.assignment_id', 44)
            ->assertJsonPath('assignments.0.code', 'EE123456789BO')
            ->assertJsonPath('assignments.0.package_type', 'ems')
            ->assertJsonPath('assignments.0.state_name', 'ASIGNADO')
            ->assertJsonPath('assignments.0.recipient_name', 'DESTINATARIO DE PRUEBA')
            ->assertJsonPath('assignments.0.recipient_phone', '70000000')
            ->assertJsonPath('assignments.0.recipient_address', 'AVENIDA DE PRUEBA 123')
            ->assertJsonPath('assignments.1.package_type', 'contrato')
            ->assertJsonPath('assignments.1.recipient_name', 'DESTINATARIO CONTRATO');

        Http::assertSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/assigned?page=1&per_page=100'
            && $request->hasHeader('Authorization', 'Bearer siop-user-token')
            && $request->hasHeader('X-API-Token', 'assigned-integration-token')
        );
    }

    public function test_courier_can_assign_only_the_codes_in_the_review_list(): void
    {
        Http::fake([
            'https://siop.example.test/assigned*' => Http::response(['data' => []]),
            'https://siop.example.test/events*' => function (Request $request) {
                $code = $request->data()['codigo'] ?? '';
                $packages = [
                    'EE123456789BO' => ['id' => 500, 'tipo' => 'ems'],
                    'CP987654321BO' => ['id' => 700, 'tipo' => 'contrato'],
                ];

                return Http::response([
                    'data' => isset($packages[$code]) ? [[
                        ...$packages[$code],
                        'codigo' => $code,
                        'eventos' => [],
                    ]] : [],
                ]);
            },
            'https://siop.example.test/assign' => Http::response([
                'message' => 'Paquetes asignados.',
                'asignados' => 2,
            ]),
        ]);

        $mobileToken = $this->issueMobileToken();

        $this->withToken($mobileToken)
            ->postJson('/api/mobile/courier/assign-packages', [
                'codes' => ['EE123456789BO', 'CP987654321BO'],
            ])
            ->assertOk()
            ->assertJsonPath('assigned_count', 2)
            ->assertJsonPath('codes.0', 'EE123456789BO')
            ->assertJsonPath('codes.1', 'CP987654321BO');

        Http::assertSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/assign'
            && $request->hasHeader('Authorization', 'Bearer siop-user-token')
            && $request->hasHeader('X-API-Token', 'assign-integration-token')
            && $request['items'] === [
                ['id' => 500, 'tipo_paquete' => 'EMS'],
                ['id' => 700, 'tipo_paquete' => 'CONTRATO'],
            ]
        );
    }

    public function test_assignment_stops_before_posting_when_a_code_does_not_exist(): void
    {
        Http::fake([
            'https://siop.example.test/assigned*' => Http::response(['data' => []]),
            'https://siop.example.test/events*' => Http::response(['data' => []]),
        ]);

        $this->withToken($this->issueMobileToken())
            ->postJson('/api/mobile/courier/assign-packages', [
                'codes' => ['EE000000000BO'],
            ])
            ->assertUnprocessable()
            ->assertJsonPath('error_code', 'SIOP_PACKAGES_NOT_FOUND');

        Http::assertNotSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/assign');
    }

    public function test_assignment_is_successful_when_siop_fails_after_committing_it(): void
    {
        $assignmentAttempted = false;

        Http::fake(function (Request $request) use (&$assignmentAttempted) {
            if (str_starts_with($request->url(), 'https://siop.example.test/events')) {
                return Http::response(['data' => [[
                    'id' => 500,
                    'tipo' => 'ems',
                    'codigo' => 'EE123456789BO',
                    'eventos' => [],
                ]]]);
            }

            if ($request->url() === 'https://siop.example.test/assign') {
                $assignmentAttempted = true;

                return Http::response(['message' => 'Fallo posterior al guardado.'], 500);
            }

            if (str_starts_with($request->url(), 'https://siop.example.test/assigned')) {
                return Http::response(['data' => $assignmentAttempted ? [[
                    'id' => 500,
                    'codigo' => 'EE123456789BO',
                    'tipo' => 'ems',
                    'estado' => 'CARTERO',
                ]] : []]);
            }

            return Http::response([], 404);
        });

        $this->withToken($this->issueMobileToken())
            ->postJson('/api/mobile/courier/assign-packages', [
                'codes' => ['EE123456789BO'],
            ])
            ->assertOk()
            ->assertJsonPath('assigned_count', 1)
            ->assertJsonPath('codes.0', 'EE123456789BO');
    }

    public function test_already_assigned_package_is_not_posted_again(): void
    {
        Http::fake([
            'https://siop.example.test/assigned*' => Http::response(['data' => [[
                'id' => 500,
                'codigo' => 'EE123456789BO',
                'tipo' => 'ems',
                'estado' => 'CARTERO',
            ]]]),
        ]);

        $this->withToken($this->issueMobileToken())
            ->postJson('/api/mobile/courier/assign-packages', [
                'codes' => ['EE123456789BO'],
            ])
            ->assertOk()
            ->assertJsonPath('assigned_count', 0)
            ->assertJsonPath('codes.0', 'EE123456789BO');

        Http::assertNotSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/assign');
    }

    private function issueMobileToken(): string
    {
        return app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Cartero de prueba',
            'alias' => 'cartero.prueba',
            'email' => 'cartero@correos.gob.bo',
            'roles' => ['cartero'],
        ], 'siop-user-token');
    }
}
