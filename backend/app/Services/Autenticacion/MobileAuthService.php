<?php

namespace App\Services\Autenticacion;

use App\Exceptions\MobileApiException;
use Illuminate\Http\Request;

class MobileAuthService
{
    private const ACCESS_PROFILE_CLASSIFICATION = 'classification';

    private const ACCESS_PROFILE_COURIER = 'courier';

    private const ACCESS_PROFILE_MANAGEMENT = 'management';

    private const ACCESS_PROFILE_UNKNOWN = 'unknown';

    private const TREATMENT_ROLE = 'tratamiento';

    private const AUXILIAR_TRATAMIENTO_ROLE = 'auxiliar_tratamiento';

    private const EMS_MANAGEMENT_ROLE = 'encargado_ems';

    private const ADMINISTRATOR_ROLE = 'administrador';

    private const CONSULTATION_ROLE = 'consulta';

    private const COURIER_EMS_ROLE = 'cartero_ems';

    private const URBAN_ASSISTANT_ROLE = 'auxiliar_urbano';

    private const EMS_MANAGEMENT_ROLE_ID = 73;

    private const COURIER_ROLE_PATTERN = '/cartero/i';

    private const AUXILIAR_ROLE_PATTERN = '/auxiliar/i';

    private const MANAGEMENT_ROLE_PATTERN = '/encargado/i';

    public function __construct(
        private readonly MobileApiTokenService $tokenService,
        private readonly SiopLoginService $siopLoginService,
    ) {}

    public function signIn(string $rawAlias, string $password): array
    {
        $alias = $this->normalizeAlias($rawAlias);
        if ($alias === '') {
            throw new MobileApiException(
                'Ingrese su alias de SIOP.',
                422,
                'ALIAS_REQUIRED',
            );
        }

        if (trim($password) === '') {
            throw new MobileApiException(
                'Ingrese su contrasena.',
                422,
                'PASSWORD_REQUIRED',
            );
        }

        $siopPayload = $this->siopLoginService->authenticate($alias, $password);
        $user = $this->buildAuthorizedUserPayload($siopPayload, $alias);
        $siopAccessToken = trim((string) ($siopPayload['access_token'] ?? ''));
        $token = $this->tokenService->issue($user, $siopAccessToken);

        return [
            'ok' => true,
            'token' => $token,
            'user' => $user,
        ];
    }

    public function authenticateRequest(Request $request): array
    {
        $payload = $this->tokenService->getPayload($request->bearerToken());

        if ($payload === null || (int) ($payload['id'] ?? 0) <= 0) {
            throw new MobileApiException(
                'La sesion expiro. Inicia sesion nuevamente.',
                401,
                'SESSION_EXPIRED',
            );
        }

        $user = $payload['user'] ?? null;
        if (! is_array($user) || (int) ($user['id'] ?? 0) <= 0) {
            throw new MobileApiException(
                'La sesion expiro. Inicia sesion nuevamente.',
                401,
                'SESSION_EXPIRED',
            );
        }

        return $user;
    }

    public function logout(?string $token): void
    {
        $this->tokenService->forget($token);
    }

    public function canManageOtherCouriers(array $authUser): bool
    {
        $roles = $this->normalizeRoles($authUser['roles'] ?? []);

        return $this->hasAdministratorRole($roles)
            || $this->resolveAccessProfile($roles) === self::ACCESS_PROFILE_MANAGEMENT;
    }

    public function canRegisterPackages(array $authUser): bool
    {
        $roles = $this->normalizeRoles($authUser['roles'] ?? []);

        return $this->hasAdministratorRole($roles)
            || $this->resolveAccessProfile($roles) === self::ACCESS_PROFILE_CLASSIFICATION;
    }

    public function canSearchPackages(array $authUser): bool
    {
        $roles = $this->normalizeRoles($authUser['roles'] ?? []);

        return $this->hasAdministratorRole($roles) || in_array($this->resolveAccessProfile($roles), [
            self::ACCESS_PROFILE_COURIER,
            self::ACCESS_PROFILE_MANAGEMENT,
        ], true);
    }

    public function isCourier(array $authUser): bool
    {
        $roles = $this->normalizeRoles($authUser['roles'] ?? []);

        return $this->hasCourierRole($roles)
            || $this->hasAdministratorRole($roles)
            || $this->hasSelfAssignableManagementRole($roles);
    }

    public function isAdministrator(array $authUser): bool
    {
        return $this->hasAdministratorRole(
            $this->normalizeRoles($authUser['roles'] ?? []),
        );
    }

    private function buildAuthorizedUserPayload(array $payload, string $loginAlias): array
    {
        $record = $this->findUserPayload($payload);
        $userId = (int) $this->firstValue($record, [
            'id',
            'user_id',
            'usuario_id',
            'id_usuario',
        ]);
        if ($userId <= 0) {
            throw new MobileApiException(
                'SIOP no devolvio el identificador del usuario autenticado.',
                502,
                'SIOP_USER_ID_MISSING',
            );
        }

        $email = $this->normalizeAlias((string) $this->firstValue(
            $record,
            ['email', 'correo', 'correo_electronico'],
            $loginAlias,
        ));
        $roles = $this->extractRoles($record);

        if ($roles === []) {
            $roles = [self::CONSULTATION_ROLE];
        }

        $allowedRoles = array_values(array_filter(
            $roles,
            fn (string $role): bool => $this->isAllowedRole($role),
        ));
        if ($allowedRoles === []) {
            throw new MobileApiException(
                'Tu usuario no tiene un rol autorizado para esta aplicacion.',
                403,
                'ROLE_NOT_ALLOWED',
            );
        }

        sort($allowedRoles);
        $accessProfile = $this->resolveAccessProfile($allowedRoles);

        $name = trim((string) $this->firstValue(
            $record,
            ['name', 'nombre', 'nombre_completo', 'alias'],
            $email,
        ));

        return [
            'id' => $userId,
            'name' => $name !== '' ? $name : $email,
            'alias' => $loginAlias,
            'email' => $email,
            'roles' => $allowedRoles,
            'access_profile' => $accessProfile,
            'capabilities' => $this->buildCapabilities($accessProfile, $allowedRoles),
        ];
    }

    private function findUserPayload(array $payload): array
    {
        $candidates = [$payload];
        foreach (['data', 'user', 'usuario'] as $key) {
            if (isset($payload[$key]) && is_array($payload[$key])) {
                $candidates[] = $payload[$key];

                foreach (['user', 'usuario'] as $nestedKey) {
                    if (isset($payload[$key][$nestedKey]) && is_array($payload[$key][$nestedKey])) {
                        $candidates[] = $payload[$key][$nestedKey];
                    }
                }
            }
        }

        foreach ($candidates as $candidate) {
            if ((int) $this->firstValue($candidate, ['id', 'user_id', 'usuario_id', 'id_usuario']) > 0) {
                return $candidate;
            }
        }

        return $payload;
    }

    private function extractRoles(array $record): array
    {
        $rawRoles = $this->firstValue($record, [
            'roles',
            'role',
            'rol',
            'perfil',
            'cargo',
            'direct_roles',
            'direct_role',
        ], []);
        $rawRoleIds = $this->firstValue($record, [
            'role_ids',
            'rol_ids',
            'id_rol',
            'role_id',
            'direct_role_ids',
            'direct_role_id',
        ], []);

        return $this->resolveRolesForUser(
            $this->flattenRoleValues($rawRoles),
            $this->flattenRoleValues($rawRoleIds),
        );
    }

    private function flattenRoleValues(mixed $value): string
    {
        if (is_array($value)) {
            $values = [];
            foreach ($value as $item) {
                if (is_array($item)) {
                    $values[] = (string) $this->firstValue($item, [
                        'name',
                        'nombre',
                        'role',
                        'rol',
                        'id',
                        'role_id',
                        'id_rol',
                    ]);
                } else {
                    $values[] = (string) $item;
                }
            }

            return implode(',', $values);
        }

        return (string) $value;
    }

    private function firstValue(array $payload, array $keys, mixed $default = null): mixed
    {
        foreach ($keys as $key) {
            if (array_key_exists($key, $payload) && $payload[$key] !== null && $payload[$key] !== '') {
                return $payload[$key];
            }
        }

        return $default;
    }

    private function resolveRolesForUser(string $directRoles, string $directRoleIds = ''): array
    {
        $roles = [];

        foreach (explode(',', $directRoles) as $directRole) {
            $normalizedDirectRole = trim(strtolower($directRole));
            if ($normalizedDirectRole !== '') {
                $roles[] = $normalizedDirectRole;
            }
        }

        foreach (explode(',', (string) $directRoleIds) as $directRoleId) {
            $roleId = (int) trim($directRoleId);
            if ($roleId === self::EMS_MANAGEMENT_ROLE_ID) {
                $roles[] = self::EMS_MANAGEMENT_ROLE;
            }
        }
        $roles = $this->normalizeRoles($roles);

        return array_values(array_unique($roles));
    }

    private function normalizeRoles(array $roles): array
    {
        return array_values(array_filter(array_map(
            fn ($role) => preg_replace(
                '/[\s-]+/',
                '_',
                trim(strtolower((string) $role)),
            ) ?? '',
            $roles,
        )));
    }

    private function accessProfileFor(array $authUser): string
    {
        return $this->resolveAccessProfile(
            $this->normalizeRoles($authUser['roles'] ?? []),
        );
    }

    private function buildCapabilities(string $accessProfile, array $roles): array
    {
        $normalizedRoles = $this->normalizeRoles($roles);
        $isAdministrator = $this->hasAdministratorRole($normalizedRoles);

        return [
            'can_manage_other_couriers' => $isAdministrator || $accessProfile === self::ACCESS_PROFILE_MANAGEMENT,
            'can_register_packages' => $isAdministrator || $accessProfile === self::ACCESS_PROFILE_CLASSIFICATION,
            'can_search_packages' => $isAdministrator || in_array($accessProfile, [
                self::ACCESS_PROFILE_COURIER,
                self::ACCESS_PROFILE_MANAGEMENT,
            ], true),
            'is_courier' => $isAdministrator
                || $accessProfile === self::ACCESS_PROFILE_COURIER
                || $this->hasSelfAssignableManagementRole($normalizedRoles)
                || $this->hasCourierRole($normalizedRoles),
        ];
    }

    private function resolveAccessProfile(array $roles): string
    {
        foreach ($roles as $role) {
            if ($this->matchesClassificationRole($role)) {
                return self::ACCESS_PROFILE_CLASSIFICATION;
            }
        }

        foreach ($roles as $role) {
            if ($this->matchesManagementRole($role)) {
                return self::ACCESS_PROFILE_MANAGEMENT;
            }
        }

        foreach ($roles as $role) {
            if ($this->matchesCourierRole($role)) {
                return self::ACCESS_PROFILE_COURIER;
            }
        }

        return self::ACCESS_PROFILE_UNKNOWN;
    }

    private function isAllowedRole(string $role): bool
    {
        return $role === self::CONSULTATION_ROLE
            || $this->matchesClassificationRole($role)
            || $this->matchesCourierRole($role)
            || $this->matchesManagementRole($role);
    }

    private function matchesClassificationRole(string $role): bool
    {
        return $role === self::TREATMENT_ROLE || $role === self::AUXILIAR_TRATAMIENTO_ROLE;
    }

    private function matchesCourierRole(string $role): bool
    {
        if ($role === self::AUXILIAR_TRATAMIENTO_ROLE) {
            return false;
        }

        return in_array($role, [self::COURIER_EMS_ROLE, self::URBAN_ASSISTANT_ROLE], true)
            || preg_match(self::COURIER_ROLE_PATTERN, $role) === 1
            || preg_match(self::AUXILIAR_ROLE_PATTERN, $role) === 1;
    }

    private function matchesManagementRole(string $role): bool
    {
        return $role === self::EMS_MANAGEMENT_ROLE
            || $role === self::ADMINISTRATOR_ROLE
            || preg_match(self::MANAGEMENT_ROLE_PATTERN, $role) === 1;
    }

    private function hasCourierRole(array $roles): bool
    {
        foreach ($roles as $role) {
            if ($this->matchesCourierRole($role)) {
                return true;
            }
        }

        return false;
    }

    private function hasAdministratorRole(array $roles): bool
    {
        return in_array(self::ADMINISTRATOR_ROLE, $roles, true);
    }

    private function hasSelfAssignableManagementRole(array $roles): bool
    {
        return in_array(self::EMS_MANAGEMENT_ROLE, $roles, true)
            || in_array((string) self::EMS_MANAGEMENT_ROLE_ID, $roles, true)
            || in_array('role_'.self::EMS_MANAGEMENT_ROLE_ID, $roles, true)
            || in_array('id_rol_'.self::EMS_MANAGEMENT_ROLE_ID, $roles, true);
    }

    private function normalizeAlias(string $alias): string
    {
        return strtolower(trim($alias));
    }
}
