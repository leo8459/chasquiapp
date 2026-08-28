<?php

namespace App\Services\Autenticacion;

use App\Exceptions\MobileApiException;
use App\Models\User;
use Illuminate\Database\Query\JoinClause;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

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

    private const EMS_MANAGEMENT_ROLE_ID = 73;

    private const COURIER_ROLE_PATTERN = '/cartero/i';

    private const AUXILIAR_ROLE_PATTERN = '/auxiliar/i';

    private const MANAGEMENT_ROLE_PATTERN = '/encargado/i';

    private const AUTHORIZED_USER_CACHE_PREFIX = 'mobile_authorized_user:';

    private const AUTHORIZED_USER_CACHE_SECONDS = 60;

    public function __construct(
        private readonly MobileApiTokenService $tokenService,
    ) {}

    public function signIn(string $rawEmail, string $password): array
    {
        $email = $this->normalizeEmail($rawEmail);
        if (! $this->isInstitutionalEmail($email)) {
            throw new MobileApiException(
                'Solo se permiten cuentas @correos.gob.bo.',
                422,
                'INVALID_EMAIL_DOMAIN',
            );
        }

        if (trim($password) === '') {
            throw new MobileApiException(
                'Ingrese su contrasena.',
                422,
                'PASSWORD_REQUIRED',
            );
        }

        $record = $this->findUserRecordByEmail($email);
        $passwordHash = trim((string) ($record->password ?? ''));

        $passwordMatches = false;
        if ($passwordHash !== '') {
            try {
                $passwordMatches = Hash::check($password, $passwordHash);
            } catch (\RuntimeException) {
                $passwordMatches = password_verify($password, $passwordHash);

                if ($passwordMatches) {
                    DB::table('users')
                        ->where('id', (int) ($record->id ?? 0))
                        ->update(['password' => Hash::make($password)]);
                }
            }
        }

        if ($passwordHash === '' || ! $passwordMatches) {
            throw new MobileApiException(
                'Usuario o contrasena incorrectos.',
                401,
                'INVALID_CREDENTIALS',
            );
        }

        $user = $this->buildAuthorizedUserPayload($record);
        $this->cacheAuthorizedUser($user);
        $token = $this->tokenService->issue($user);

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

        $userId = (int) $payload['id'];

        return Cache::remember(
            $this->authorizedUserCacheKey($userId),
            now()->addSeconds(self::AUTHORIZED_USER_CACHE_SECONDS),
            fn (): array => $this->buildAuthorizedUserPayload(
                $this->findUserRecordById($userId),
            ),
        );
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

    private function findUserRecordByEmail(string $email): object
    {
        $record = DB::table('users as u')
            ->leftJoin('model_has_roles as mhr', function (JoinClause $join): void {
                $join->on('mhr.model_id', '=', 'u.id')
                    ->where('mhr.model_type', User::class);
            })
            ->leftJoin('roles as r', 'r.id', '=', 'mhr.role_id')
            ->select([
                'u.id',
                'u.name',
                'u.email',
                'u.password',
                DB::raw("coalesce(string_agg(distinct lower(coalesce(r.name, '')), ','), '') as direct_roles"),
                DB::raw("coalesce(string_agg(distinct coalesce(r.id, mhr.role_id)::text, ','), '') as direct_role_ids"),
            ])
            ->whereRaw('lower(u.email) = ?', [$email])
            ->whereNull('u.deleted_at')
            ->groupBy('u.id', 'u.name', 'u.email', 'u.password')
            ->first();

        if ($record === null) {
            throw new MobileApiException(
                'Usuario o contrasena incorrectos.',
                401,
                'INVALID_CREDENTIALS',
            );
        }

        return $record;
    }

    private function findUserRecordById(int $userId): object
    {
        $record = DB::table('users as u')
            ->leftJoin('model_has_roles as mhr', function (JoinClause $join): void {
                $join->on('mhr.model_id', '=', 'u.id')
                    ->where('mhr.model_type', User::class);
            })
            ->leftJoin('roles as r', 'r.id', '=', 'mhr.role_id')
            ->select([
                'u.id',
                'u.name',
                'u.email',
                'u.password',
                DB::raw("coalesce(string_agg(distinct lower(coalesce(r.name, '')), ','), '') as direct_roles"),
                DB::raw("coalesce(string_agg(distinct coalesce(r.id, mhr.role_id)::text, ','), '') as direct_role_ids"),
            ])
            ->where('u.id', $userId)
            ->whereNull('u.deleted_at')
            ->groupBy('u.id', 'u.name', 'u.email', 'u.password')
            ->first();

        if ($record === null) {
            throw new MobileApiException(
                'La sesion expiro. Inicia sesion nuevamente.',
                401,
                'SESSION_EXPIRED',
            );
        }

        return $record;
    }

    private function buildAuthorizedUserPayload(object $record): array
    {
        $userId = (int) ($record->id ?? 0);
        if ($userId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar el usuario autenticado.',
                422,
                'INVALID_USER_ID',
            );
        }

        $email = $this->normalizeEmail((string) ($record->email ?? ''));
        $roles = $this->resolveRolesForUser(
            (string) ($record->direct_roles ?? $record->direct_role ?? ''),
            (string) ($record->direct_role_ids ?? $record->direct_role_id ?? ''),
        );

        if ($roles === []) {
            throw new MobileApiException(
                'Tu cuenta no tiene roles asignados en el backend.',
                403,
                'ROLES_REQUIRED',
            );
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

        $name = trim((string) ($record->name ?? ''));

        return [
            'id' => $userId,
            'name' => $name !== '' ? $name : $email,
            'email' => $email,
            'roles' => $allowedRoles,
            'access_profile' => $accessProfile,
            'capabilities' => $this->buildCapabilities($accessProfile, $allowedRoles),
        ];
    }

    private function cacheAuthorizedUser(array $user): void
    {
        $userId = (int) ($user['id'] ?? 0);
        if ($userId <= 0) {
            return;
        }

        Cache::put(
            $this->authorizedUserCacheKey($userId),
            $user,
            now()->addSeconds(self::AUTHORIZED_USER_CACHE_SECONDS),
        );
    }

    private function authorizedUserCacheKey(int $userId): string
    {
        return self::AUTHORIZED_USER_CACHE_PREFIX.$userId;
    }

    private function resolveRolesForUser(string $directRoles, string|int $directRoleIds = ''): array
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
            fn ($role) => trim(strtolower((string) $role)),
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
        return $this->matchesClassificationRole($role)
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

        return preg_match(self::COURIER_ROLE_PATTERN, $role) === 1
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

    private function normalizeEmail(string $email): string
    {
        return strtolower(trim($email));
    }

    private function isInstitutionalEmail(string $email): bool
    {
        return $email !== '' && str_ends_with($email, '@correos.gob.bo');
    }
}
