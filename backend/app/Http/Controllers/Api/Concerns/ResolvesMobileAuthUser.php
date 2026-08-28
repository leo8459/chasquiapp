<?php

namespace App\Http\Controllers\Api\Concerns;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Request;

trait ResolvesMobileAuthUser
{
    protected function mobileAuthUser(Request $request): array
    {
        $authUser = $request->attributes->get('mobile_auth_user');

        if (! is_array($authUser) || (int) ($authUser['id'] ?? 0) <= 0) {
            throw new MobileApiException(
                'La sesion expiro. Inicia sesion nuevamente.',
                401,
                'SESSION_EXPIRED',
            );
        }

        return $authUser;
    }
}
