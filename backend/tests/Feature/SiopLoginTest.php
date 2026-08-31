<?php

namespace Tests\Feature;

use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SiopLoginTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config([
            'cache.default' => 'array',
            'services.siop_login.url' => 'https://siop.example.test/login',
            'services.siop_login.token' => 'integration-token',
            'services.siop_login.verify_ssl' => true,
        ]);
    }

    public function test_login_uses_siop_api_and_keeps_the_user_in_the_mobile_session(): void
    {
        Http::fake([
            'https://siop.example.test/login' => Http::response([
                'data' => [
                    'usuario' => [
                        'id_usuario' => 321,
                        'nombre' => 'Usuario SIOP',
                        'correo' => 'usuario@correos.gob.bo',
                        'roles' => [
                            ['nombre' => 'cartero'],
                        ],
                    ],
                ],
            ]),
        ]);

        $loginResponse = $this->postJson('/api/mobile/auth/login', [
            'alias' => 'usuario.siop',
            'password' => 'clave-secreta',
        ]);

        $loginResponse
            ->assertOk()
            ->assertJsonPath('user.id', 321)
            ->assertJsonPath('user.alias', 'usuario.siop')
            ->assertJsonPath('user.email', 'usuario@correos.gob.bo')
            ->assertJsonPath('user.roles.0', 'cartero');

        $token = (string) $loginResponse->json('token');
        $this->withToken($token)
            ->getJson('/api/mobile/auth/me')
            ->assertOk()
            ->assertJsonPath('user.id', 321)
            ->assertJsonPath('user.name', 'Usuario SIOP');

        Http::assertSent(fn (Request $request): bool => $request->url() === 'https://siop.example.test/login'
            && $request->hasHeader('Authorization', 'Bearer integration-token')
            && $request['alias'] === 'usuario.siop'
            && $request['password'] === 'clave-secreta'
        );
    }

    public function test_invalid_siop_credentials_are_returned_as_unauthorized(): void
    {
        Http::fake([
            'https://siop.example.test/login' => Http::response([
                'message' => 'El usuario o la contrasena son incorrectos.',
            ], 401),
        ]);

        $this->postJson('/api/mobile/auth/login', [
            'alias' => 'usuario.siop',
            'password' => 'incorrecta',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('error_code', 'INVALID_CREDENTIALS');
    }

    public function test_authenticated_siop_user_without_roles_gets_read_only_access(): void
    {
        Http::fake([
            'https://siop.example.test/login' => Http::response([
                'message' => 'Inicio de sesion SIOP correcto.',
                'user' => [
                    'id' => 81,
                    'name' => 'Usuario sin roles',
                    'alias' => 'usuario.siop',
                    'email' => 'usuario@correos.gob.bo',
                ],
            ]),
        ]);

        $this->postJson('/api/mobile/auth/login', [
            'alias' => 'usuario.siop',
            'password' => 'clave-secreta',
        ])
            ->assertOk()
            ->assertJsonPath('user.alias', 'usuario.siop')
            ->assertJsonPath('user.roles.0', 'consulta')
            ->assertJsonPath('user.capabilities.can_manage_other_couriers', false)
            ->assertJsonPath('user.capabilities.can_register_packages', false)
            ->assertJsonPath('user.capabilities.can_search_packages', false);
    }

    public function test_siop_courier_ems_and_urban_assistant_roles_are_authorized(): void
    {
        Http::fake([
            'https://siop.example.test/login' => Http::response([
                'user' => [
                    'id' => 90,
                    'name' => 'Cartero autorizado',
                    'alias' => 'cartero.siop',
                    'email' => 'cartero@correos.gob.bo',
                    'roles' => ['cartero_ems', 'auxiliar urbano'],
                ],
                'access_token' => 'siop-courier-token',
            ]),
        ]);

        $this->postJson('/api/mobile/auth/login', [
            'alias' => 'cartero.siop',
            'password' => 'clave-secreta',
        ])
            ->assertOk()
            ->assertJsonPath('user.roles.0', 'auxiliar_urbano')
            ->assertJsonPath('user.roles.1', 'cartero_ems')
            ->assertJsonPath('user.access_profile', 'courier')
            ->assertJsonPath('user.capabilities.is_courier', true)
            ->assertJsonPath('user.capabilities.can_search_packages', true);
    }
}
