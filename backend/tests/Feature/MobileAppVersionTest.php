<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class MobileAppVersionTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config([
            'app.url' => 'https://example.test/chasquiapp',
            'mobile.download_url' => '',
            'cache.default' => 'array',
        ]);
        Http::preventStrayRequests();
    }

    public function test_public_policy_exposes_download_link_with_application_prefix(): void
    {
        $this->withHeader('X-App-Version', '')
            ->getJson('/api/mobile/app-version')
            ->assertOk()
            ->assertJsonPath('required_version', '1.0.5+6')
            ->assertJsonPath('download_url', 'https://example.test/chasquiapp/descargas/')
            ->assertJsonPath('update_required', true);
    }

    public function test_same_version_is_allowed_by_the_policy(): void
    {
        $this->getJson('/api/mobile/app-version')->assertOk()
            ->assertJsonPath('update_required', false);

        // La solicitud pasa el control de versión y alcanza la validación del login.
        $this->postJson('/api/mobile/auth/login', [])->assertUnprocessable();
    }

    public function test_missing_old_newer_malformed_and_different_build_are_blocked_before_login(): void
    {
        Http::fake();
        foreach (['', '1.0.4+5', '1.0.5+5', '1.0.5', '2.0.0+7', 'invalid'] as $version) {
            $this->withHeader('X-App-Version', $version)
                ->postJson('/api/mobile/auth/login', ['alias' => 'usuario', 'password' => 'clave'])
                ->assertStatus(426)
                ->assertJsonPath('error_code', 'APP_UPDATE_REQUIRED')
                ->assertJsonPath('required_version', '1.0.5+6');
        }
        Http::assertNothingSent();
    }

    public function test_remembered_sessions_and_protected_requests_are_also_blocked(): void
    {
        foreach (['/api/mobile/auth/me', '/api/mobile/courier/assigned-packages'] as $path) {
            $this->withHeader('X-App-Version', '1.0.4+5')
                ->withToken('previously-issued-token')
                ->getJson($path)->assertStatus(426);
        }
    }

    public function test_policy_change_immediately_blocks_previously_current_client(): void
    {
        $this->getJson('/api/mobile/app-version')->assertJsonPath('update_required', false);
        config(['mobile.required_version' => '1.0.6+7']);
        $this->postJson('/api/mobile/auth/login', [])->assertStatus(426)
            ->assertJsonPath('required_version', '1.0.6+7');
    }

    public function test_custom_download_url_is_returned(): void
    {
        config(['mobile.download_url' => 'https://downloads.example.test/app.apk']);
        $this->getJson('/api/mobile/app-version')->assertOk()
            ->assertJsonPath('download_url', 'https://downloads.example.test/app.apk');
    }

    public function test_invalid_policy_fails_closed(): void
    {
        config(['mobile.required_version' => '']);
        $this->postJson('/api/mobile/auth/login', [])->assertStatus(503);
        $this->getJson('/api/mobile/app-version')->assertStatus(503);
        config(['mobile.required_version' => '1.0.5+6', 'mobile.download_url' => 'javascript:alert(1)']);
        $this->getJson('/api/mobile/app-version')->assertStatus(503);
    }
}
