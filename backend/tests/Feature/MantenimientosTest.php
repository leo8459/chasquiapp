<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MantenimientosTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_mantenimientos.url' => 'https://siop.example.test/mantenimientos',
            'services.siop_mantenimientos.token' => 'mantenimientos-token',
            'services.siop_mantenimientos.verify_ssl' => true,
        ]);
    }

    public function test_authenticated_user_can_list_mantenimientos(): void
    {
        Http::fake([
            'https://siop.example.test/mantenimientos*' => Http::response([
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 20,
                'total' => 1,
                'data' => [[
                    'id' => 14,
                    'vehicle_id' => 6,
                    'fecha_programada' => '2026-09-15',
                    'estado' => 'Programado',
                    'vehicle' => ['id' => 6, 'placa' => 'LEO 8459', 'marca' => 'FERRARI'],
                    'maintenance_type' => ['id' => 3, 'nombre' => 'PASTILLAS'],
                ]],
            ]),
        ]);

        $this->withToken($this->issueToken())
            ->getJson('/api/mobile/mantenimientos')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.vehicle_plate', 'LEO 8459')
            ->assertJsonPath('data.0.maintenance_type', 'PASTILLAS');

        Http::assertSent(fn (Request $request): bool =>
            $request->hasHeader('Authorization', 'Bearer mantenimientos-token'));
    }

    public function test_authenticated_user_can_load_mantenimiento_options(): void
    {
        Http::fake([
            'https://siop.example.test/mantenimientos/vehiculos' => Http::response([
                'data' => [['id' => 6, 'placa' => 'LEO 8459', 'vehicle_class' => 'FERRARI 2026', 'disponible_para_mantenimiento' => true]],
            ]),
            'https://siop.example.test/mantenimientos/tipos' => Http::response([
                'data' => [['id' => 3, 'nombre' => 'PASTILLAS', 'categoria_label' => 'Programado por KM']],
            ]),
        ]);

        $this->withToken($this->issueToken())
            ->getJson('/api/mobile/mantenimientos/opciones')
            ->assertOk()
            ->assertJsonPath('vehicles.0.plate', 'LEO 8459')
            ->assertJsonPath('maintenance_types.0.name', 'PASTILLAS');
    }

    public function test_authenticated_user_can_create_a_mantenimiento(): void
    {
        Http::fake([
            'https://siop.example.test/mantenimientos' => Http::response([
                'message' => 'Solicitud creada correctamente.',
                'data' => ['id' => 15, 'vehicle_id' => 6, 'maintenance_type_id' => 3, 'fecha_programada' => '2026-09-20'],
            ], 201),
        ]);

        $this->withToken($this->issueToken())
            ->postJson('/api/mobile/mantenimientos', [
                'vehicle_id' => 6,
                'maintenance_type_id' => 3,
                'fecha_programada' => '2026-09-20',
            ])
            ->assertCreated()
            ->assertJsonPath('message', 'Solicitud creada correctamente.')
            ->assertJsonPath('mantenimiento.id', 15);

        Http::assertSent(fn (Request $request): bool =>
            $request->url() === 'https://siop.example.test/mantenimientos'
            && $request->hasHeader('Authorization', 'Bearer mantenimientos-token')
            && $request['vehicle_id'] === 6
            && $request['maintenance_type_id'] === 3);
    }

    public function test_create_requires_all_fields_before_calling_siop(): void
    {
        Http::fake();

        $this->withToken($this->issueToken())
            ->postJson('/api/mobile/mantenimientos', [])
            ->assertUnprocessable()
            ->assertJsonPath('error_code', 'VALIDATION_ERROR');

        Http::assertNothingSent();
    }

    private function issueToken(): string
    {
        return app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Usuario de prueba',
            'alias' => 'usuario.prueba',
            'email' => 'usuario@correos.gob.bo',
            'roles' => ['cartero'],
        ]);
    }
}
