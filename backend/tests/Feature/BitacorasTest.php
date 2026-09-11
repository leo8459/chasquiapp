<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class BitacorasTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_bitacoras.url' => 'https://siop.example.test/bitacoras',
            'services.siop_bitacoras.read_token' => 'bitacoras-integration-token',
            'services.siop_bitacoras.create_token' => 'bitacoras-create-token',
            'services.siop_bitacoras.verify_ssl' => true,
        ]);
    }

    public function test_administrator_can_list_paginated_bitacoras(): void
    {
        Http::fake([
            'https://siop.example.test/bitacoras*' => Http::response([
                'current_page' => 2,
                'last_page' => 3,
                'per_page' => 20,
                'total' => 45,
                'from' => 21,
                'to' => 40,
                'data' => [[
                    'id' => 7,
                    'fecha' => '2026-09-10T04:00:00.000000Z',
                    'kilometraje_salida' => '52.00',
                    'kilometraje_llegada' => '61.50',
                    'recorrido_inicio' => 'La Paz',
                    'recorrido_destino' => 'El Alto',
                    'abastecimiento_combustible' => true,
                    'activo' => false,
                    'cantidad_paquetes' => 12,
                    'driver' => ['id' => 1, 'nombre' => 'Ana', 'telefono' => '70000000'],
                    'vehicle' => ['id' => 2, 'placa' => 'ABC-123', 'marca' => 'Toyota'],
                ]],
            ]),
        ]);

        $this->withToken($this->issueToken(['administrador']))
            ->getJson('/api/mobile/bitacoras?page=2&per_page=20')
            ->assertOk()
            ->assertJsonPath('current_page', 2)
            ->assertJsonPath('total', 45)
            ->assertJsonPath('data.0.id', 7)
            ->assertJsonPath('data.0.driver.nombre', 'Ana')
            ->assertJsonPath('data.0.vehicle.placa', 'ABC-123');

        Http::assertSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/bitacoras?page=2&per_page=20'
            && $request->hasHeader('Authorization', 'Bearer bitacoras-integration-token')
        );
    }

    public function test_authenticated_courier_can_list_bitacoras(): void
    {
        Http::fake([
            'https://siop.example.test/bitacoras*' => Http::response([
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 20,
                'total' => 0,
                'data' => [],
            ]),
        ]);

        $this->withToken($this->issueToken(['cartero']))
            ->getJson('/api/mobile/bitacoras')
            ->assertOk()
            ->assertJsonPath('total', 0);

        Http::assertSentCount(1);
    }

    public function test_authenticated_user_can_load_vehicle_and_driver_catalogs(): void
    {
        Http::fake([
            'https://siop.example.test/bitacoras/vehiculos' => Http::response([
                'count' => 1,
                'data' => [[
                    'id' => 6,
                    'placa' => 'LEO 8459',
                    'marca' => 'FERRARI',
                    'modelo' => 'ULTIMO',
                    'activo' => true,
                ]],
            ]),
            'https://siop.example.test/bitacoras/conductores' => Http::response([
                'count' => 1,
                'data' => [[
                    'id' => 4,
                    'nombre' => 'VARGAS PABLO',
                    'activo' => true,
                ]],
            ]),
        ]);

        $token = $this->issueToken(['cartero']);

        $this->withToken($token)
            ->getJson('/api/mobile/bitacoras/vehiculos')
            ->assertOk()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('data.0.placa', 'LEO 8459');

        $this->withToken($token)
            ->getJson('/api/mobile/bitacoras/conductores')
            ->assertOk()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('data.0.nombre', 'VARGAS PABLO');

        Http::assertSent(function (Request $request): bool {
            return in_array($request->url(), [
                'https://siop.example.test/bitacoras/vehiculos',
                'https://siop.example.test/bitacoras/conductores',
            ], true) && $request->hasHeader('Authorization', 'Bearer bitacoras-create-token');
        });
    }

    public function test_authenticated_user_can_create_a_bitacora_with_photo(): void
    {
        Http::fake([
            'https://siop.example.test/bitacoras' => Http::response([
                'message' => 'Bitacora creada correctamente.',
                'data' => [
                    'id' => 8,
                    'fecha' => '2026-09-10T04:00:00.000000Z',
                    'driver' => ['id' => 1, 'nombre' => 'Ana'],
                    'vehicle' => ['id' => 2, 'placa' => 'ABC-123'],
                ],
            ], 201),
        ]);

        $this->withToken($this->issueToken(['cartero']))
            ->post('/api/mobile/bitacoras', [
                'vehicles_id' => 2,
                'drivers_id' => 1,
                'fecha' => '2026-09-10',
                'kilometraje_salida' => 52,
                'kilometraje_recorrido' => 9.5,
                'recorrido_inicio' => 'La Paz',
                'recorrido_destino' => 'El Alto',
                'latitud_inicio' => -16.50,
                'logitud_inicio' => -68.15,
                'latitud_destino' => -16.51,
                'logitud_destino' => -68.16,
                'odometro_photo' => UploadedFile::fake()->image('odometro.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('message', 'Bitacora creada correctamente.')
            ->assertJsonPath('bitacora.id', 8);

        Http::assertSent(function (Request $request): bool {
            $parts = collect($request->data());
            $hasPart = fn (string $name, string $value): bool => $parts->contains(
                fn (array $part): bool => ($part['name'] ?? null) === $name
                    && (string) ($part['contents'] ?? '') === $value,
            );

            return $request->url() === 'https://siop.example.test/bitacoras'
                && $request->hasHeader('Authorization', 'Bearer bitacoras-create-token')
                && $request->hasFile('odometro_photo')
                && $hasPart('vehicles_id', '2')
                && $hasPart('drivers_id', '1');
        });
    }

    public function test_create_bitacora_requires_all_fields_before_calling_siop(): void
    {
        Http::fake();

        $this->withToken($this->issueToken(['cartero']))
            ->postJson('/api/mobile/bitacoras', [])
            ->assertUnprocessable()
            ->assertJsonPath('error_code', 'VALIDATION_ERROR');

        Http::assertNothingSent();
    }

    private function issueToken(array $roles): string
    {
        return app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Usuario de prueba',
            'alias' => 'usuario.prueba',
            'email' => 'usuario@correos.gob.bo',
            'roles' => $roles,
        ]);
    }
}
