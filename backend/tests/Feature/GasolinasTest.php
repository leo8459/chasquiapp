<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class GasolinasTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_gasolinas.url' => 'https://siop.example.test/gasolinas',
            'services.siop_gasolinas.read_token' => 'gasolinas-read-token',
            'services.siop_gasolinas.create_token' => 'gasolinas-create-token',
            'services.siop_gasolinas.verify_ssl' => true,
        ]);
    }

    public function test_authenticated_user_can_list_gasolina_records(): void
    {
        Http::fake([
            'https://siop.example.test/gasolinas*' => Http::response([
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 20,
                'total' => 1,
                'data' => [[
                    'id' => 1,
                    'station_name' => 'Estación Central',
                    'total_amount' => 55.05,
                    'date_time' => '2026-09-10T08:00:00-04:00',
                    'invoice_number' => '31198',
                    'vehicle_plate' => 'ABC-123',
                    'driver_name' => 'Ana',
                    'vehicle_id' => 2,
                    'driver_id' => 1,
                    'liters' => 7.91,
                    'unit_price' => 6.96,
                    'estado' => 'Verificado',
                ]],
            ]),
        ]);

        $this->withToken($this->issueToken())
            ->getJson('/api/mobile/gasolinas')
            ->assertOk()
            ->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.invoice_number', '31198')
            ->assertJsonPath('data.0.vehicle_plate', 'ABC-123');

        Http::assertSent(fn (Request $request): bool =>
            $request->hasHeader('Authorization', 'Bearer gasolinas-read-token'));
    }

    public function test_authenticated_user_can_create_a_gasolina_record(): void
    {
        Http::fake([
            'https://siop.example.test/gasolinas' => Http::response([
                'message' => 'Registro creado correctamente.',
                'data' => ['id' => 2, 'invoice_number' => '31200'],
            ], 201),
        ]);

        $this->withToken($this->issueToken())
            ->post('/api/mobile/gasolinas', [
                'vehicle_id' => 2,
                'driver_id' => 1,
                'numero_factura' => '31200',
                'nombre_cliente' => 'AGENCIA BOLIVIANA DE CORREOS',
                'fecha_emision' => '2026-09-10T00:00:00-04:00',
                'cantidad' => 10.5,
                'precio_unitario' => 6.96,
                'invoice_photo' => UploadedFile::fake()->image('factura.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('message', 'Registro creado correctamente.')
            ->assertJsonPath('gasolina.id', 2);

        Http::assertSent(function (Request $request): bool {
            $parts = collect($request->data());
            $hasPart = fn (string $name, string $value): bool => $parts->contains(
                fn (array $part): bool => ($part['name'] ?? null) === $name
                    && (string) ($part['contents'] ?? '') === $value,
            );

            return $request->url() === 'https://siop.example.test/gasolinas'
                && $request->hasHeader('Authorization', 'Bearer gasolinas-create-token')
                && $request->hasFile('invoice_photo')
                && $hasPart('vehicle_id', '2')
                && $hasPart('numero_factura', '31200');
        });
    }

    public function test_create_requires_all_fields_before_calling_siop(): void
    {
        Http::fake();

        $this->withToken($this->issueToken())
            ->postJson('/api/mobile/gasolinas', [])
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
