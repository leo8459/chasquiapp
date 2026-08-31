<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class TrackingEventsTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'services.siop_tracking_events.url' => 'https://siop.example.test/paquetes-eventos',
            'services.siop_tracking_events.token' => 'events-token',
            'services.siop_tracking_events.verify_ssl' => true,
        ]);
    }

    public function test_tracking_view_receives_nested_siop_events_normalized_as_a_timeline(): void
    {
        Http::fake([
            'https://siop.example.test/paquetes-eventos*' => Http::response([
                'data' => [[
                    'tipo' => 'ems',
                    'id' => 10,
                    'codigo' => 'EE123456789BO',
                    'cantidad_eventos' => 2,
                    'eventos' => [
                        [
                            'id' => 100,
                            'evento_id' => 5,
                            'nombre' => 'Recibido en oficina',
                            'detalle' => 'Paquete registrado en ventanilla.',
                            'usuario' => ['id' => 81, 'nombre' => 'Operador SIOP'],
                            'fecha' => '2026-08-31T10:15:00-04:00',
                        ],
                        [
                            'id' => 101,
                            'evento_id' => 6,
                            'nombre' => 'En transito',
                            'detalle' => 'Despachado hacia destino.',
                            'usuario' => ['id' => 82, 'nombre' => 'Clasificacion'],
                            'fecha' => '2026-08-31T11:20:00-04:00',
                        ],
                    ],
                ]],
                'paginacion' => [
                    'pagina_actual' => 1,
                    'por_pagina' => 30,
                    'total_registros' => 1,
                ],
            ]),
        ]);

        $this->getJson('/api/tracking/events?code=EE123456789BO&limit=30')
            ->assertOk()
            ->assertJsonPath('filtro.codigo', 'EE123456789BO')
            ->assertJsonPath('filtro.tabla', 'eventos_ems')
            ->assertJsonPath('filtro.exacto', true)
            ->assertJsonPath('total', 2)
            ->assertJsonPath('data.0.evento', 'Recibido en oficina')
            ->assertJsonPath('data.0.detalle', 'Paquete registrado en ventanilla.')
            ->assertJsonPath('data.0.usuario', 'Operador SIOP')
            ->assertJsonPath('data.1.created_at', '2026-08-31T11:20:00-04:00');

        Http::assertSent(fn (Request $request): bool => $request->hasHeader('Authorization', 'Bearer events-token')
            && $request->data()['codigo'] === 'EE123456789BO'
            && $request->data()['per_page'] === 30
        );
    }
}
