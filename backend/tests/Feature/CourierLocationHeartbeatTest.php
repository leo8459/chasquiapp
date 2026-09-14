<?php

namespace Tests\Feature;

use App\Services\Autenticacion\MobileApiTokenService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class CourierLocationHeartbeatTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_courier_location.url' => 'https://siop.example.test/api/chasqui/location/heartbeat',
            'services.siop_courier_location.token' => 'location-integration-token',
            'services.siop_courier_location.verify_ssl' => true,
        ]);
    }

    public function test_courier_location_is_published_with_siop_session_and_integration_token(): void
    {
        Http::fake([
            'https://siop.example.test/api/chasqui/location/heartbeat' => Http::response([
                'message' => 'Ubicacion actualizada.',
            ]),
        ]);

        $mobileToken = $this->mobileToken('siop-user-token');

        $this->withToken($mobileToken)
            ->postJson('/api/mobile/courier/location/heartbeat', [
                'latitude' => -16.4897,
                'longitude' => -68.1193,
                'accuracy' => 4.2,
                'altitude' => 3640.5,
                'speed' => 1.7,
                'heading' => 90,
                'captured_at' => '2026-09-14T13:30:00Z',
            ])
            ->assertOk()
            ->assertJsonPath('ok', true)
            ->assertJsonPath('message', 'Ubicacion actualizada.');

        Http::assertSent(fn (Request $request): bool => $request->method() === 'POST'
            && $request->url() === 'https://siop.example.test/api/chasqui/location/heartbeat'
            && $request->hasHeader('Authorization', 'Bearer siop-user-token')
            && $request->hasHeader('X-API-Token', 'location-integration-token')
            && $request['latitude'] === -16.4897
            && $request['longitude'] === -68.1193
            && $request['captured_at'] === '2026-09-14T13:30:00Z'
        );
    }

    public function test_authenticated_client_can_read_latest_courier_locations(): void
    {
        Http::fake([
            'https://siop.example.test/api/chasqui/location/heartbeat' => Http::response([
                'updated_at' => '2026-09-14T09:14:53-04:00',
                'count' => 1,
                'data' => [[
                    'user_id' => 81,
                    'latitude' => -16.4897,
                    'longitude' => -68.1193,
                ]],
            ]),
        ]);

        $this->withToken($this->mobileToken('siop-user-token'))
            ->getJson('/api/mobile/courier/location/heartbeat')
            ->assertOk()
            ->assertJsonPath('count', 1)
            ->assertJsonPath('data.0.user_id', 81);

        Http::assertSent(fn (Request $request): bool => $request->method() === 'GET'
            && $request->hasHeader('Authorization', 'Bearer location-integration-token')
            && $request->hasHeader('X-API-Token', 'location-integration-token')
        );
    }

    public function test_location_coordinates_are_validated_before_calling_siop(): void
    {
        Http::fake();

        $this->withToken($this->mobileToken('siop-user-token'))
            ->postJson('/api/mobile/courier/location/heartbeat', [
                'latitude' => -100,
                'longitude' => -68.1193,
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('latitude');

        Http::assertNothingSent();
    }

    private function mobileToken(string $siopToken): string
    {
        return app(MobileApiTokenService::class)->issue([
            'id' => 81,
            'name' => 'Cartero de prueba',
            'email' => 'cartero@correos.gob.bo',
            'roles' => ['cartero'],
        ], $siopToken);
    }
}
