<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SiopPackageLookupTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'services.siop_tracking_events.url' => 'https://siop.example.test/events',
            'services.siop_tracking_events.token' => 'events-token',
            'services.siop_tracking_events.verify_ssl' => true,
        ]);
    }

    public function test_package_search_uses_siop_api_instead_of_the_local_database(): void
    {
        Http::fake([
            'https://siop.example.test/events*' => Http::response([
                'data' => [[
                    'tipo' => 'contrato',
                    'id' => 701,
                    'codigo' => 'C0013A04291BO',
                    'destino' => 'LA PAZ',
                    'peso' => '0.250',
                    'estado' => ['id' => 13, 'nombre' => 'CARTERO'],
                    'destinatario' => [
                        'nombre' => 'DESTINATARIO API',
                        'telefono' => '70000000',
                        'direccion' => 'AVENIDA API 123',
                    ],
                    'eventos' => [],
                ]],
            ]),
        ]);

        $this->getJson('/api/tracking/package?code=C0013A04291BO')
            ->assertOk()
            ->assertJsonPath('found', true)
            ->assertJsonPath('package_id', 701)
            ->assertJsonPath('package_type', 'contrato')
            ->assertJsonPath('recipient_name', 'DESTINATARIO API')
            ->assertJsonPath('phone', '70000000')
            ->assertJsonPath('highlight_location', 'AVENIDA API 123')
            ->assertJsonPath('city', 'LA PAZ');

        Http::assertSent(fn (Request $request): bool => str_starts_with(
            $request->url(),
            'https://siop.example.test/events?'
        ) && $request->hasHeader('Authorization', 'Bearer events-token'));
    }

    public function test_package_search_returns_not_found_when_siop_has_no_exact_code(): void
    {
        Http::fake([
            'https://siop.example.test/events*' => Http::response(['data' => []]),
        ]);

        $this->getJson('/api/tracking/package?code=EE000000000BO')
            ->assertNotFound()
            ->assertJsonPath('error_code', 'PACKAGE_NOT_FOUND');
    }
}
