<?php

namespace App\Services\OperacionesPostales;

use App\Exceptions\MobileApiException;
use App\Models\User;
use App\Services\Autenticacion\MobileAuthService;
use App\Support\Database\PublicSchemaInspector;
use Illuminate\Database\Query\Builder;
use Illuminate\Database\Query\JoinClause;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class MobilePackageTrackingService
{
    private const ACTIVE_ASSIGNMENT_STATES = ['ASIGNADO', 'CARTERO', 'DOMICILIO'];

    private const WAREHOUSE_STATE = 'ALMACEN';

    private const WAREHOUSE_STATE_ID = 1;

    private const WINDOW_STATE = 'VENTANILLA';

    private const WINDOW_STATE_ID = 2;

    private const RECEIVED_STATE_ID = 10;

    private const LEGACY_INVENTORY_STATE = 'INVENTARIO';

    private const ASSIGNED_STATE = 'ASIGNADO';

    private const IN_PROGRESS_STATE = 'CARTERO';

    private const IN_PROGRESS_STATE_ID = 13;

    private const DEVOLUTION_STATE = 'DEVOLUCION';

    private const DEVOLUTION_STATE_ID = 18;

    private const DELIVERED_STATE_ID = 27;

    private const DELIVERED_STATE_NAME = 'ENTREGADO';

    private const INVENTORY_PACKAGES_CACHE_TTL_SECONDS = 3600;

    private const INVENTORY_PACKAGES_CACHE_LOCK_SECONDS = 120;

    private const INVENTORY_PACKAGES_CACHE_LOCK_WAIT_SECONDS = 15;

    private const INVENTORY_PACKAGES_CACHE_KEY_VERSION = 'v3';

    private const INVENTORY_PACKAGES_CACHE_VERSION_KEY = 'mobile_inventory_packages_version';

    private const DATABASE_TIMESTAMP_FORMAT = 'Y-m-d H:i:s.v';

    private const RECEIVED_BY_PATTERN =
        '/^([A-ZÁÉÍÓÚÑ][a-záéíóúñ]+(?:[-\s][A-ZÁÉÍÓÚÑ][a-záéíóúñ]+)*)$/u';

    private const RECEIVED_BY_VOWEL_PATTERN = '/[AEIOUÁÉÍÓÚaeiouáéíóú]/u';

    public function __construct(
        private readonly MobileAuthService $authService,
        private readonly PublicSchemaInspector $schemaInspector,
    ) {}

    public function findAssignmentsForUser(array $authUser, int $targetUserId): array
    {
        $this->ensureCanAccessAssignments($authUser, $targetUserId);

        if ($targetUserId <= 0) {
            return [];
        }

        return $this->queryAssignmentsForUser($targetUserId);
    }

    private function queryAssignmentsForUser(int $targetUserId): array
    {
        $rows = DB::select(self::assignmentsSql(), [
            $targetUserId,
            $targetUserId,
            $targetUserId,
            $targetUserId,
        ]);

        return array_values(array_filter(array_map(function (object $row): ?array {
            $assignmentId = (int) ($row->assignment_id ?? 0);
            $code = trim((string) ($row->code ?? ''));
            $packageType = trim((string) ($row->package_type ?? ''));
            $stateName = trim((string) ($row->state_name ?? ''));
            $createdAt = $row->created_at ?? null;

            if ($assignmentId <= 0 || $code === '' || $packageType === '' || $stateName === '') {
                return null;
            }

            return [
                'assignment_id' => $assignmentId,
                'code' => $code,
                'package_type' => $packageType,
                'state_name' => $stateName,
                'created_at' => $createdAt instanceof \DateTimeInterface
                    ? $createdAt->format('c')
                    : ($createdAt !== null ? (string) $createdAt : null),
            ];
        }, $rows)));
    }

    public function findAvailableCouriers(array $authUser, bool $allCities = false): array
    {
        $this->ensureCanManageOtherCouriers($authUser);

        $canViewAllCities = $allCities && $this->authService->isAdministrator($authUser);
        $city = $canViewAllCities ? 'TODAS LAS CIUDADES' : $this->resolveManagementCity($authUser);
        $rows = $this->availableCouriersQueryForCity(
            $canViewAllCities ? null : $city,
            $authUser,
        )
            ->orderByDesc('active_assignments_count')
            ->orderBy('u.ciudad')
            ->orderBy('u.name')
            ->get();

        return [
            'city' => $city,
            'couriers' => $rows
                ->map(fn (object $row): array => $this->mapCourierSummary($row))
                ->values()
                ->all(),
        ];
    }

    public function findCourierByCi(array $authUser, string $rawCi): ?array
    {
        $this->ensureCanManageOtherCouriers($authUser);
        $city = $this->resolveManagementCity($authUser);

        $normalizedCi = $this->normalizeCi($rawCi);
        if ($normalizedCi === '') {
            return null;
        }

        $user = $this->availableCouriersQueryForCity($city, $authUser)
            ->whereRaw(
                "upper(regexp_replace(coalesce(u.ci::text, ''), '[^A-Za-z0-9]', '', 'g')) = ?",
                [$normalizedCi],
            )
            ->orderBy('u.id')
            ->first();

        if ($user === null) {
            return null;
        }

        return $this->mapCourierSummary($user);
    }

    public function findInventoryPackagesForCourier(array $authUser, int $targetUserId): array
    {
        $courier = $this->resolveCourierForManagementCity($authUser, $targetUserId);
        $city = strtoupper(trim((string) ($courier['city'] ?? '')));

        return [
            'city' => $city,
            'courier' => $courier,
            'packages' => $this->cachedInventoryPackagesForCity($city),
        ];
    }

    public function findRecentRegionalAssignedPackages(array $authUser): array
    {
        $this->ensureCanManageOtherCouriers($authUser);
        $city = $this->resolveManagementCity($authUser);
        $todayStart = now('America/La_Paz')->startOfDay();
        $tomorrowStart = $todayStart->copy()->addDay();

        $rows = DB::select(self::regionalRecentAssignedSql(), [
            $city,
            $city,
            $city,
            $city,
            $todayStart->format(self::DATABASE_TIMESTAMP_FORMAT),
            $tomorrowStart->format(self::DATABASE_TIMESTAMP_FORMAT),
        ]);

        return array_values(array_filter(array_map(function (object $row): ?array {
            $assignmentId = (int) ($row->assignment_id ?? 0);
            $code = trim((string) ($row->code ?? ''));
            $packageType = trim((string) ($row->package_type ?? ''));
            $stateName = trim((string) ($row->state_name ?? ''));
            $createdAt = $row->created_at ?? null;

            if ($assignmentId <= 0 || $code === '' || $packageType === '' || $stateName === '') {
                return null;
            }

            return [
                'assignment_id' => $assignmentId,
                'code' => strtoupper($code),
                'package_type' => $packageType,
                'state_name' => $stateName,
                'created_at' => $createdAt instanceof \DateTimeInterface
                    ? $createdAt->format('c')
                    : ($createdAt !== null ? (string) $createdAt : null),
                'courier_user_id' => (int) ($row->courier_user_id ?? 0),
                'courier_name' => trim((string) ($row->courier_name ?? '')),
            ];
        }, $rows)));
    }

    public function assignInventoryPackageToCourier(
        array $authUser,
        int $targetUserId,
        string $packageType,
        int $packageId,
    ): array {
        if ($packageId <= 0) {
            throw new MobileApiException(
                'Debes seleccionar un paquete valido para asignar.',
                422,
                'PACKAGE_REQUIRED',
            );
        }

        $courier = $this->resolveCourierForManagementCity($authUser, $targetUserId);
        $assignment = DB::transaction(fn (): array => $this->assignInventoryPackageRecord(
            courier: $courier,
            targetUserId: $targetUserId,
            packageType: $packageType,
            packageId: $packageId,
        ));
        $this->bumpInventoryPackagesCacheVersion($assignment['city'] ?? $courier['city'] ?? '');

        return [
            'ok' => true,
            'assignment_id' => $assignment['assignment_id'],
            'courier_user_id' => (int) ($courier['id'] ?? 0),
            'active_assignments_count' => $this->activeAssignmentsCountForCourier($targetUserId),
            'package_type' => $assignment['package_type'],
            'package_id' => $assignment['package_id'],
            'code' => $assignment['code'],
            'recipient_name' => $assignment['recipient_name'],
            'city' => $assignment['city'],
            'state_name' => self::IN_PROGRESS_STATE,
            'message' => 'Paquete asignado correctamente al cartero.',
        ];
    }

    public function assignInventoryPackagesToCourier(
        array $authUser,
        int $targetUserId,
        string $packageType,
        array $packageIds,
    ): array {
        $normalizedPackageIds = array_values(array_filter(array_map(
            static fn ($value): int => (int) $value,
            $packageIds,
        ), static fn (int $value): bool => $value > 0));

        if ($normalizedPackageIds === []) {
            throw new MobileApiException(
                'Debes seleccionar al menos un paquete valido para asignar.',
                422,
                'PACKAGE_REQUIRED',
            );
        }

        $courier = $this->resolveCourierForManagementCity($authUser, $targetUserId);
        $assignments = DB::transaction(function () use (
            $courier,
            $targetUserId,
            $packageType,
            $normalizedPackageIds,
        ): array {
            $results = [];
            foreach ($normalizedPackageIds as $packageId) {
                $results[] = $this->assignInventoryPackageRecord(
                    courier: $courier,
                    targetUserId: $targetUserId,
                    packageType: $packageType,
                    packageId: $packageId,
                );
            }

            return $results;
        });
        $this->bumpInventoryPackagesCacheVersion($courier['city'] ?? '');

        return [
            'ok' => true,
            'courier_user_id' => (int) ($courier['id'] ?? 0),
            'active_assignments_count' => $this->activeAssignmentsCountForCourier($targetUserId),
            'package_type' => $packageType,
            'package_ids' => array_values(array_map(
                static fn (array $assignment): int => (int) ($assignment['package_id'] ?? 0),
                $assignments,
            )),
            'assignments' => $assignments,
            'assigned_count' => count($assignments),
            'state_name' => self::IN_PROGRESS_STATE,
            'message' => count($assignments) === 1
                ? 'Paquete asignado correctamente al cartero.'
                : 'Paquetes asignados correctamente al cartero.',
        ];
    }

    private function assignInventoryPackageRecord(
        array $courier,
        int $targetUserId,
        string $packageType,
        int $packageId,
    ): array {
        $city = strtoupper(trim((string) ($courier['city'] ?? '')));
        $assignedStateId = self::IN_PROGRESS_STATE_ID;
        $config = $this->resolvePackageSourceConfig($packageType);
        $assignableStateIds = $this->assignableInventoryStateIds($config);
        $tableColumns = $this->getTableColumns($config['table']);
        $stateColumn = $this->pickFirstExistingColumn($tableColumns, $config['state_columns']);

        if ($stateColumn === null) {
            throw new MobileApiException(
                "La tabla {$config['table']} no tiene una columna de estado compatible.",
                503,
                'PACKAGE_STATE_COLUMN_NOT_FOUND',
            );
        }

        $cityExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['city_columns'],
            fallback: "''",
        );
        $codeExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['code_columns'],
            fallback: "''",
        );
        $recipientExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['recipient_columns'],
            fallback: "'Sin destinatario'",
        );

        $packageRow = DB::table("{$config['table']} as p")
            ->selectRaw(
                "p.{$config['id_column']} as package_id, p.{$stateColumn} as package_state_id, {$codeExpression} as code, {$recipientExpression} as recipient_name, {$cityExpression} as city",
            )
            ->where("p.{$config['id_column']}", $packageId)
            ->whereIn("p.{$stateColumn}", $assignableStateIds)
            ->whereRaw("upper(btrim({$cityExpression})) = ?", [$city])
            ->whereRaw("nullif(btrim({$codeExpression}), '') is not null")
            ->lockForUpdate()
            ->first();

        if ($packageRow === null) {
            throw new MobileApiException(
                'El paquete seleccionado ya no esta disponible para asignar en esta ciudad.',
                409,
                'PACKAGE_NOT_AVAILABLE',
            );
        }

        $createdAt = $this->currentDatabaseTimestamp();

        $assignmentRow = DB::table('cartero as c')
            ->select([
                'c.id',
                'c.id_user',
                'c.id_estados',
                DB::raw(
                    "(SELECT upper(btrim(coalesce(e.nombre_estado, ''))) "
                    .'FROM estados as e WHERE e.id = c.id_estados) as state_name',
                ),
            ])
            ->where("c.{$config['cartero_foreign_key']}", $packageId)
            ->orderByRaw('c.updated_at DESC NULLS LAST')
            ->orderByDesc('c.id')
            ->lockForUpdate()
            ->first();

        if ($assignmentRow !== null) {
            $existingStateName = strtoupper(trim((string) ($assignmentRow->state_name ?? '')));
            $existingCourierId = (int) ($assignmentRow->id_user ?? 0);
            if (
                in_array($existingStateName, self::ACTIVE_ASSIGNMENT_STATES, true)
                && $existingCourierId > 0
                && $existingCourierId !== $targetUserId
            ) {
                throw new MobileApiException(
                    'Este paquete ya tiene una asignación activa con otro cartero.',
                    409,
                    'PACKAGE_ALREADY_ASSIGNED',
                );
            }

            $assignmentId = (int) ($assignmentRow->id ?? 0);
            DB::table('cartero')
                ->where('id', $assignmentId)
                ->update([
                    'id_estados' => $assignedStateId,
                    'id_user' => $targetUserId,
                    'updated_at' => $createdAt,
                ]);
        } else {
            $assignmentId = DB::table('cartero')->insertGetId([
                $config['cartero_foreign_key'] => $packageId,
                'id_estados' => $assignedStateId,
                'id_user' => $targetUserId,
                'created_at' => $createdAt,
                'updated_at' => $createdAt,
            ]);
        }

        $updateValues = [$stateColumn => $assignedStateId];
        if (in_array('updated_at', $tableColumns, true)) {
            $updateValues['updated_at'] = $createdAt;
        }

        DB::table($config['table'])
            ->where($config['id_column'], $packageId)
            ->update($updateValues);

        return [
            'assignment_id' => (int) $assignmentId,
            'package_type' => $config['package_type'],
            'package_id' => (int) ($packageRow->package_id ?? 0),
            'code' => trim((string) ($packageRow->code ?? '')),
            'recipient_name' => trim((string) ($packageRow->recipient_name ?? '')),
            'city' => strtoupper(trim((string) ($packageRow->city ?? ''))),
            'state_name' => self::IN_PROGRESS_STATE,
        ];
    }

    public function confirmDelivered(
        array $authUser,
        int $assignmentId,
        int $courierUserId,
        string $receivedBy,
        UploadedFile $deliveryPhoto,
        UploadedFile $deliverySignature,
    ): array {
        if ($assignmentId <= 0) {
            throw new MobileApiException(
                'No se encontró la asignación a actualizar.',
                422,
                'ASSIGNMENT_REQUIRED',
            );
        }

        if ($courierUserId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar al cartero.',
                422,
                'COURIER_REQUIRED',
            );
        }

        $receivedBy = $this->normalizeReceivedBy($receivedBy);
        $this->ensureValidReceivedBy($receivedBy);

        $this->ensureCanConfirmDelivery($authUser, $courierUserId);

        $deliveredStateId = $this->resolveDeliveredStateId();

        $carteroColumns = $this->getTableColumns('cartero');
        $photoColumn = in_array('foto', $carteroColumns, true) ? 'foto' : null;
        if ($photoColumn === null) {
            throw new MobileApiException(
                'La tabla cartero debe tener la columna foto para guardar el comprobante.',
                503,
                'PHOTO_COLUMN_NOT_FOUND',
            );
        }
        $signatureColumn = in_array('imagen', $carteroColumns, true) ? 'imagen' : null;
        if ($signatureColumn === null) {
            throw new MobileApiException(
                'La tabla cartero debe tener la columna imagen para guardar la firma.',
                503,
                'SIGNATURE_COLUMN_NOT_FOUND',
            );
        }
        if (! in_array('recibido_por', $carteroColumns, true)) {
            throw new MobileApiException(
                'La tabla cartero no tiene la columna recibido_por para guardar este dato.',
                503,
                'RECEIVED_BY_COLUMN_NOT_FOUND',
            );
        }

        $photoRelativePath = $this->storeDeliveryPhoto($assignmentId, $deliveryPhoto);
        try {
            $signatureRelativePath = $this->storeDeliverySignature($assignmentId, $deliverySignature);
        } catch (\Throwable $exception) {
            $this->deleteStoredDeliveryEvidence($photoRelativePath);

            throw $exception;
        }
        $updatedAt = $this->currentDatabaseTimestamp();

        try {
            DB::beginTransaction();
            $updatedRows = DB::select(
                <<<SQL
                UPDATE cartero
                SET
                  id_estados = ?,
                  recibido_por = ?,
                  {$photoColumn} = ?,
                  {$signatureColumn} = ?,
                  updated_at = ?
                WHERE id = ?
                  AND id_user = ?
                  AND upper(
                    btrim(
                      coalesce(
                        (SELECT nombre_estado FROM estados WHERE id = cartero.id_estados),
                        ''
                      )
                    )
                  ) IN (?, ?, ?)
                RETURNING id
                SQL,
                [
                    $deliveredStateId,
                    $receivedBy,
                    $photoRelativePath,
                    $signatureRelativePath,
                    $updatedAt,
                    $assignmentId,
                    $courierUserId,
                    self::ACTIVE_ASSIGNMENT_STATES[0],
                    self::ACTIVE_ASSIGNMENT_STATES[1],
                    self::ACTIVE_ASSIGNMENT_STATES[2],
                ],
            );

            if ($updatedRows === []) {
                $this->deleteStoredDeliveryEvidence($photoRelativePath, $signatureRelativePath);

                throw new MobileApiException(
                    'La asignación ya no está activa o no pertenece al cartero actual.',
                    409,
                    'ASSIGNMENT_NOT_ACTIVE',
                );
            }

            $this->updateAssignedPackageFields(
                assignmentId: $assignmentId,
                courierUserId: $courierUserId,
                updatedAt: $updatedAt,
            );

            DB::commit();
        } catch (MobileApiException $exception) {
            DB::rollBack();
            $this->deleteStoredDeliveryEvidence($photoRelativePath, $signatureRelativePath);

            throw $exception;
        } catch (\Throwable $exception) {
            DB::rollBack();
            $this->deleteStoredDeliveryEvidence($photoRelativePath, $signatureRelativePath);

            throw $exception;
        }

        return [
            'ok' => true,
            'assignment_id' => $assignmentId,
            'courier_user_id' => $courierUserId,
            'active_assignments_count' => $this->activeAssignmentsCountForCourier($courierUserId),
            'state_id' => $deliveredStateId,
            'state_name' => self::DELIVERED_STATE_NAME,
            'received_by' => $receivedBy,
            'photo_path' => $photoRelativePath,
            'photo_url' => Storage::disk('public')->url($photoRelativePath),
            'signature_path' => $signatureRelativePath,
            'signature_url' => Storage::disk('public')->url($signatureRelativePath),
            'updated_at' => $updatedAt,
            'message' => 'Entrega confirmada correctamente.',
        ];
    }

    public function registerDevolutionAttempt(
        array $authUser,
        int $assignmentId,
        int $courierUserId,
        string $description,
        UploadedFile $deliveryAttemptPhoto,
    ): array {
        if ($assignmentId <= 0) {
            throw new MobileApiException(
                'No se encontro la asignacion a actualizar.',
                422,
                'ASSIGNMENT_REQUIRED',
            );
        }

        if ($courierUserId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar al cartero.',
                422,
                'COURIER_REQUIRED',
            );
        }

        $normalizedDescription = trim(preg_replace('/\s+/u', ' ', $description) ?? '');
        if ($normalizedDescription === '') {
            throw new MobileApiException(
                'Debes describir lo ocurrido para registrar la devolucion.',
                422,
                'DESCRIPTION_REQUIRED',
            );
        }

        $this->ensureCanConfirmDelivery($authUser, $courierUserId);

        $carteroColumns = $this->getTableColumns('cartero');
        if (! in_array('descripcion', $carteroColumns, true)) {
            throw new MobileApiException(
                'La tabla cartero no tiene la columna descripcion para guardar el motivo.',
                503,
                'DESCRIPTION_COLUMN_NOT_FOUND',
            );
        }
        if (! in_array('intento', $carteroColumns, true)) {
            throw new MobileApiException(
                'La tabla cartero no tiene la columna intento para registrar visitas.',
                503,
                'ATTEMPT_COLUMN_NOT_FOUND',
            );
        }
        if (! in_array('imagen_devolucion', $carteroColumns, true)) {
            throw new MobileApiException(
                'La tabla cartero no tiene la columna imagen_devolucion para guardar la evidencia.',
                503,
                'DEVOLUTION_IMAGE_COLUMN_NOT_FOUND',
            );
        }

        $devolutionStateId = self::DEVOLUTION_STATE_ID;
        $photoRelativePath = $this->storeDevolutionPhoto($assignmentId, $deliveryAttemptPhoto);
        $updatedAt = $this->currentDatabaseTimestamp();
        $previousPhotoRelativePath = null;

        try {
            $updatedRows = DB::transaction(function () use (
                $assignmentId,
                $courierUserId,
                $devolutionStateId,
                $normalizedDescription,
                $photoRelativePath,
                $updatedAt,
                &$previousPhotoRelativePath,
            ): array {
                $assignment = DB::table('cartero')
                    ->select('imagen_devolucion')
                    ->where('id', $assignmentId)
                    ->where('id_user', $courierUserId)
                    ->whereRaw(
                        "upper(btrim(coalesce((SELECT nombre_estado FROM estados WHERE id = cartero.id_estados), ''))) IN (?, ?, ?, ?)",
                        [
                            self::ACTIVE_ASSIGNMENT_STATES[0],
                            self::ACTIVE_ASSIGNMENT_STATES[1],
                            self::ACTIVE_ASSIGNMENT_STATES[2],
                            self::DEVOLUTION_STATE,
                        ],
                    )
                    ->lockForUpdate()
                    ->first();

                if ($assignment === null) {
                    throw new MobileApiException(
                        'La asignacion ya no esta activa o no pertenece al cartero actual.',
                        409,
                        'ASSIGNMENT_NOT_ACTIVE',
                    );
                }

                $previousPhotoRelativePath = trim((string) ($assignment->imagen_devolucion ?? ''));

                $updatedRows = DB::select(
                    <<<'SQL'
                    UPDATE cartero
                    SET
                      id_estados = ?,
                      descripcion = ?::text,
                      imagen_devolucion = ?,
                      intento = coalesce(intento, 0) + 1,
                      updated_at = ?
                    WHERE id = ?
                      AND id_user = ?
                      AND upper(
                        btrim(
                          coalesce(
                            (SELECT nombre_estado FROM estados WHERE id = cartero.id_estados),
                            ''
                          )
                        )
                      ) IN (?, ?, ?, ?)
                    RETURNING
                      id,
                      intento,
                      id_estados,
                      descripcion,
                      (SELECT nombre_estado FROM estados WHERE id = cartero.id_estados) AS state_name
                    SQL,
                    [
                        $devolutionStateId,
                        $normalizedDescription,
                        $photoRelativePath,
                        $updatedAt,
                        $assignmentId,
                        $courierUserId,
                        self::ACTIVE_ASSIGNMENT_STATES[0],
                        self::ACTIVE_ASSIGNMENT_STATES[1],
                        self::ACTIVE_ASSIGNMENT_STATES[2],
                        self::DEVOLUTION_STATE,
                    ],
                );

                if ($updatedRows === []) {
                    throw new MobileApiException(
                        'La asignacion ya no esta activa o no pertenece al cartero actual.',
                        409,
                        'ASSIGNMENT_NOT_ACTIVE',
                    );
                }

                $this->updateAssignedPackageFields(
                    assignmentId: $assignmentId,
                    courierUserId: $courierUserId,
                    updatedAt: $updatedAt,
                    stateId: $devolutionStateId,
                );

                return $updatedRows;
            });
        } catch (MobileApiException $exception) {
            $this->deleteStoredDeliveryEvidence($photoRelativePath);

            throw $exception;
        } catch (\Throwable $exception) {
            $this->deleteStoredDeliveryEvidence($photoRelativePath);

            throw $exception;
        }

        if ($previousPhotoRelativePath !== null && $previousPhotoRelativePath !== $photoRelativePath) {
            $this->deleteStoredDeliveryEvidence($previousPhotoRelativePath);
        }

        $attemptCount = (int) ($updatedRows[0]->intento ?? 0);
        $stateId = (int) ($updatedRows[0]->id_estados ?? 0);
        $stateName = strtoupper(trim((string) ($updatedRows[0]->state_name ?? self::DEVOLUTION_STATE)));
        $fullDescription = trim((string) ($updatedRows[0]->descripcion ?? ''));

        return [
            'ok' => true,
            'assignment_id' => $assignmentId,
            'courier_user_id' => $courierUserId,
            'active_assignments_count' => $this->activeAssignmentsCountForCourier($courierUserId),
            'state_id' => $stateId,
            'state_name' => $stateName,
            'description' => $fullDescription,
            'attempt_count' => $attemptCount,
            'devolution_image_path' => $photoRelativePath,
            'devolution_image_url' => Storage::disk('public')->url($photoRelativePath),
            'updated_at' => $updatedAt,
            'message' => 'Intento registrado correctamente.',
        ];
    }

    public function updateAssignmentStatus(
        array $authUser,
        int $assignmentId,
        int $courierUserId,
        string $rawStatus,
    ): array {
        if ($assignmentId <= 0) {
            throw new MobileApiException(
                'No se encontro la asignacion a actualizar.',
                422,
                'ASSIGNMENT_REQUIRED',
            );
        }

        if ($courierUserId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar al cartero.',
                422,
                'COURIER_REQUIRED',
            );
        }

        $this->ensureCanConfirmDelivery($authUser, $courierUserId);

        $targetStateName = $this->normalizeAssignmentStatusName($rawStatus);
        $targetStateId = $this->findStateIdByName($targetStateName);
        $updatedAt = $this->currentDatabaseTimestamp();

        if ($targetStateId === null) {
            throw new MobileApiException(
                "No existe el estado {$targetStateName} en la base de datos.",
                503,
                'ASSIGNMENT_STATE_NOT_FOUND',
            );
        }

        $updatedRows = DB::select(
            <<<'SQL'
            UPDATE cartero
            SET
              id_estados = ?,
              updated_at = ?
            WHERE id = ?
              AND id_user = ?
              AND upper(
                btrim(
                  coalesce(
                    (SELECT nombre_estado FROM estados WHERE id = cartero.id_estados),
                    ''
                  )
                )
              ) IN (?, ?, ?)
            RETURNING id
            SQL,
            [
                $targetStateId,
                $updatedAt,
                $assignmentId,
                $courierUserId,
                self::ACTIVE_ASSIGNMENT_STATES[0],
                self::ACTIVE_ASSIGNMENT_STATES[1],
                self::ACTIVE_ASSIGNMENT_STATES[2],
            ],
        );

        if ($updatedRows === []) {
            throw new MobileApiException(
                'La asignacion ya no esta activa o no pertenece al cartero actual.',
                409,
                'ASSIGNMENT_NOT_ACTIVE',
            );
        }

        return [
            'ok' => true,
            'assignment_id' => $assignmentId,
            'courier_user_id' => $courierUserId,
            'active_assignments_count' => $this->activeAssignmentsCountForCourier($courierUserId),
            'state_id' => $targetStateId,
            'state_name' => $targetStateName,
            'updated_at' => $updatedAt,
            'message' => $targetStateName === self::IN_PROGRESS_STATE
                ? 'Estado actualizado a EN PROGRESO.'
                : 'Estado actualizado a ASIGNADO.',
        ];
    }

    public function revertAssignmentToWarehouse(
        array $authUser,
        int $targetUserId,
        int $assignmentId,
    ): array {
        if ($assignmentId <= 0) {
            throw new MobileApiException(
                'No se encontro la asignacion a revertir.',
                422,
                'ASSIGNMENT_REQUIRED',
            );
        }

        $courier = $this->resolveCourierForManagementCity($authUser, $targetUserId);
        $city = strtoupper(trim((string) ($courier['city'] ?? '')));
        $warehouseStateId = $this->resolveWarehouseStateId();
        $updatedAt = $this->currentDatabaseTimestamp();

        $result = DB::transaction(function () use (
            $assignmentId,
            $targetUserId,
            $city,
            $warehouseStateId,
            $updatedAt,
        ): array {
            $assignment = DB::table('cartero as c')
                ->join('estados as e', 'e.id', '=', 'c.id_estados')
                ->select([
                    'c.id',
                    'c.id_user',
                    'c.id_paquetes_ems',
                    'c.id_paquetes_certi',
                    'c.id_paquetes_contrato',
                    'c.id_paquetes_ordi',
                    'c.created_at',
                    DB::raw('e.nombre_estado as state_name'),
                ])
                ->where('c.id', $assignmentId)
                ->where('c.id_user', $targetUserId)
                ->whereRaw(
                    "upper(btrim(coalesce(e.nombre_estado, ''))) IN (?, ?, ?)",
                    [
                        self::ACTIVE_ASSIGNMENT_STATES[0],
                        self::ACTIVE_ASSIGNMENT_STATES[1],
                        self::ACTIVE_ASSIGNMENT_STATES[2],
                    ],
                )
                ->lockForUpdate()
                ->first();

            if ($assignment === null) {
                throw new MobileApiException(
                    'La asignacion ya no esta activa o no pertenece al cartero seleccionado.',
                    409,
                    'ASSIGNMENT_NOT_ACTIVE',
                );
            }

            $config = null;
            $packageId = 0;
            foreach ($this->packageSourceConfigs() as $candidateConfig) {
                $candidatePackageId = (int) ($assignment->{$candidateConfig['cartero_foreign_key']} ?? 0);
                if ($candidatePackageId > 0) {
                    $config = $candidateConfig;
                    $packageId = $candidatePackageId;
                    break;
                }
            }

            if ($config === null || $packageId <= 0) {
                throw new MobileApiException(
                    'No se pudo identificar el paquete de esta asignacion.',
                    409,
                    'ASSIGNMENT_PACKAGE_NOT_FOUND',
                );
            }

            $tableColumns = $this->getTableColumns($config['table']);
            $stateColumn = $this->pickFirstExistingColumn($tableColumns, $config['state_columns']);
            if ($stateColumn === null) {
                throw new MobileApiException(
                    "La tabla {$config['table']} no tiene una columna de estado compatible.",
                    503,
                    'PACKAGE_STATE_COLUMN_NOT_FOUND',
                );
            }

            $cityExpression = $this->buildCoalescedTextExpression(
                alias: 'p',
                availableColumns: $tableColumns,
                preferredColumns: $config['city_columns'],
                fallback: "''",
            );
            $codeExpression = $this->buildCoalescedTextExpression(
                alias: 'p',
                availableColumns: $tableColumns,
                preferredColumns: $config['code_columns'],
                fallback: "''",
            );
            $recipientExpression = $this->buildCoalescedTextExpression(
                alias: 'p',
                availableColumns: $tableColumns,
                preferredColumns: $config['recipient_columns'],
                fallback: "'Sin destinatario'",
            );

            $packageRow = DB::table("{$config['table']} as p")
                ->selectRaw(
                    "p.{$config['id_column']} as package_id, {$codeExpression} as code, {$recipientExpression} as recipient_name, {$cityExpression} as city",
                )
                ->where("p.{$config['id_column']}", $packageId)
                ->whereRaw("upper(btrim({$cityExpression})) = ?", [$city])
                ->lockForUpdate()
                ->first();

            if ($packageRow === null) {
                throw new MobileApiException(
                    'El paquete no pertenece a la ciudad operativa actual.',
                    403,
                    'PACKAGE_CITY_MISMATCH',
                );
            }

            $packageUpdateValues = [$stateColumn => $warehouseStateId];
            if (in_array('updated_at', $tableColumns, true)) {
                $packageUpdateValues['updated_at'] = $updatedAt;
            }

            DB::table($config['table'])
                ->where($config['id_column'], $packageId)
                ->update($packageUpdateValues);

            DB::table('cartero')
                ->where('id', $assignmentId)
                ->where('id_user', $targetUserId)
                ->update([
                    'id_estados' => $warehouseStateId,
                    'updated_at' => $updatedAt,
                ]);

            return [
                'ok' => true,
                'assignment_id' => $assignmentId,
                'courier_user_id' => $targetUserId,
                'package_type' => $config['package_type'],
                'package_id' => (int) ($packageRow->package_id ?? 0),
                'code' => strtoupper(trim((string) ($packageRow->code ?? ''))),
                'recipient_name' => trim((string) ($packageRow->recipient_name ?? '')),
                'city' => strtoupper(trim((string) ($packageRow->city ?? ''))),
                'state_name' => self::WAREHOUSE_STATE,
                'updated_at' => $updatedAt,
                'message' => 'Asignacion revertida y paquete devuelto a ALMACEN.',
            ];
        });

        $this->bumpInventoryPackagesCacheVersion($result['city'] ?? $city);
        $result['active_assignments_count'] = $this->activeAssignmentsCountForCourier($targetUserId);

        return $result;
    }

    private function activeAssignmentsCountForCourier(int $courierUserId): int
    {
        if ($courierUserId <= 0) {
            return 0;
        }

        return (int) DB::table('cartero as c')
            ->join('estados as e', 'e.id', '=', 'c.id_estados')
            ->where('c.id_user', $courierUserId)
            ->whereRaw(
                "upper(btrim(coalesce(e.nombre_estado, ''))) IN (?, ?, ?)",
                [
                    self::ACTIVE_ASSIGNMENT_STATES[0],
                    self::ACTIVE_ASSIGNMENT_STATES[1],
                    self::ACTIVE_ASSIGNMENT_STATES[2],
                ],
            )
            ->count();
    }

    private function ensureCanAccessAssignments(array $authUser, int $targetUserId): void
    {
        if ($targetUserId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar al usuario solicitado.',
                422,
                'USER_REQUIRED',
            );
        }

        if ((int) ($authUser['id'] ?? 0) === $targetUserId) {
            if ($this->authService->isCourier($authUser)) {
                return;
            }

            throw new MobileApiException(
                'No tienes permisos para consultar tus asignaciones.',
                403,
                'FORBIDDEN_OWN_ASSIGNMENTS',
            );
        }

        $this->ensureCanManageOtherCouriers($authUser);
    }

    private function ensureCanManageOtherCouriers(array $authUser): void
    {
        if (! $this->authService->canManageOtherCouriers($authUser)) {
            throw new MobileApiException(
                'No tienes permisos para consultar asignaciones de otros carteros.',
                403,
                'FORBIDDEN_COURIER_LOOKUP',
            );
        }
    }

    private function ensureCanConfirmDelivery(array $authUser, int $courierUserId): void
    {
        if ((int) ($authUser['id'] ?? 0) === $courierUserId) {
            if ($this->authService->isCourier($authUser)) {
                return;
            }

            throw new MobileApiException(
                'No tienes permisos para actualizar tus asignaciones.',
                403,
                'FORBIDDEN_ASSIGNMENT_UPDATE',
            );
        }

        $this->ensureCanManageOtherCouriers($authUser);
    }

    private function isSelfAssignableManagementUser(?array $authUser): bool
    {
        if ($authUser === null) {
            return false;
        }

        $roles = array_map(
            static fn ($role): string => trim(strtolower((string) $role)),
            $authUser['roles'] ?? [],
        );

        return in_array('encargado_ems', $roles, true)
            || in_array('73', $roles, true)
            || in_array('role_73', $roles, true)
            || in_array('id_rol_73', $roles, true);
    }

    private function normalizeCi(string $rawCi): string
    {
        return strtoupper(trim(preg_replace('/[^A-Z0-9]/i', '', $rawCi) ?? ''));
    }

    private function normalizeReceivedBy(string $rawValue): string
    {
        $normalized = preg_replace('/\s*-\s*/u', '-', $rawValue) ?? '';
        $normalized = preg_replace('/\s+/u', ' ', $normalized) ?? '';
        $normalized = trim($normalized);
        if ($normalized === '') {
            return '';
        }

        $words = preg_split('/\s+/u', $normalized) ?: [];
        $normalizedWords = array_map(function (string $word): string {
            $parts = preg_split('/-/u', $word) ?: [];
            $normalizedParts = array_map(function (string $part): string {
                $lower = mb_strtolower(trim($part), 'UTF-8');
                if ($lower === '') {
                    return '';
                }

                return mb_strtoupper(mb_substr($lower, 0, 1, 'UTF-8'), 'UTF-8')
                    .mb_substr($lower, 1, null, 'UTF-8');
            }, $parts);

            return implode('-', array_values(array_filter($normalizedParts, static fn (string $part): bool => $part !== '')));
        }, $words);

        return implode(' ', array_values(array_filter($normalizedWords, static fn (string $word): bool => $word !== '')));
    }

    private function ensureValidReceivedBy(string $receivedBy): void
    {
        if ($receivedBy === '') {
            throw new MobileApiException(
                'Escribe el nombre y apellido de quien recibe el paquete.',
                422,
                'RECEIVED_BY_REQUIRED',
            );
        }

        if (! preg_match('/^[A-Za-zÁÉÍÓÚÑáéíóúñ\s-]+$/u', $receivedBy)) {
            throw new MobileApiException(
                'El nombre de quien recibe solo puede tener letras, espacios o guion.',
                422,
                'RECEIVED_BY_INVALID_CHARACTERS',
            );
        }

        $parts = preg_split('/[\s-]+/u', $receivedBy) ?: [];
        foreach ($parts as $part) {
            if ($part === '') {
                continue;
            }

            if (mb_strlen($part, 'UTF-8') < 2) {
                throw new MobileApiException(
                    'Cada nombre o apellido debe tener al menos 2 letras completas.',
                    422,
                    'RECEIVED_BY_PART_TOO_SHORT',
                );
            }

            if (! preg_match(self::RECEIVED_BY_VOWEL_PATTERN, $part)) {
                throw new MobileApiException(
                    'Revisa el nombre ingresado. No uses abreviaturas ni bloques de consonantes.',
                    422,
                    'RECEIVED_BY_INVALID_TOKEN',
                );
            }
        }

        if (! preg_match(self::RECEIVED_BY_PATTERN, $receivedBy)) {
            throw new MobileApiException(
                'Escribe un nombre valido, por ejemplo: Juan Perez o Maria-Laura.',
                422,
                'RECEIVED_BY_INVALID_FORMAT',
            );
        }
    }

    private function resolveManagementCity(array $authUser): string
    {
        $city = DB::table('users')
            ->where('id', (int) ($authUser['id'] ?? 0))
            ->value('ciudad');

        $normalizedCity = strtoupper(trim((string) $city));
        if ($normalizedCity === '') {
            throw new MobileApiException(
                'Tu usuario no tiene una ciudad configurada para consultar carteros.',
                422,
                'MANAGEMENT_CITY_REQUIRED',
            );
        }

        return $normalizedCity;
    }

    private function availableCouriersQueryForCity(
        ?string $city,
        ?array $authUser = null,
    ): Builder {
        $activeAssignmentsSubquery = DB::table('cartero as c')
            ->join('estados as e', 'e.id', '=', 'c.id_estados')
            ->selectRaw('c.id_user as user_id, count(*) as active_assignments_count')
            ->whereRaw(
                "upper(btrim(coalesce(e.nombre_estado, ''))) IN (?, ?, ?)",
                [
                    self::ACTIVE_ASSIGNMENT_STATES[0],
                    self::ACTIVE_ASSIGNMENT_STATES[1],
                    self::ACTIVE_ASSIGNMENT_STATES[2],
                ],
            )
            ->groupBy('c.id_user');

        $query = DB::table('users as u')
            ->join('model_has_roles as mhr', function (JoinClause $join): void {
                $join->on('mhr.model_id', '=', 'u.id')
                    ->where('mhr.model_type', User::class);
            })
            ->join('roles as r', 'r.id', '=', 'mhr.role_id')
            ->leftJoinSub($activeAssignmentsSubquery, 'active_assignments', function ($join): void {
                $join->on('active_assignments.user_id', '=', 'u.id');
            })
            ->select([
                'u.id',
                'u.name',
                'u.email',
                'u.ci',
                'u.ciudad',
                DB::raw("lower(coalesce(r.name, '')) as role_name"),
                DB::raw('coalesce(active_assignments.active_assignments_count, 0) as active_assignments_count'),
            ])
            ->whereNull('u.deleted_at')
            ->where(function (Builder $query) use ($authUser): void {
                $query->whereRaw("lower(coalesce(r.name, '')) like ?", ['%cartero%'])
                    ->orWhere(function (Builder $nestedQuery): void {
                        $nestedQuery
                            ->whereRaw("lower(coalesce(r.name, '')) like ?", ['%auxiliar%'])
                            ->whereRaw("lower(coalesce(r.name, '')) <> ?", ['auxiliar_tratamiento']);
                    });

                if ($this->isSelfAssignableManagementUser($authUser)) {
                    $query->orWhere(function (Builder $nestedQuery) use ($authUser): void {
                        $nestedQuery
                            ->where('u.id', (int) ($authUser['id'] ?? 0))
                            ->where(function (Builder $roleQuery): void {
                                $roleQuery
                                    ->whereRaw("lower(coalesce(r.name, '')) = ?", ['encargado_ems'])
                                    ->orWhere('r.id', 73);
                            });
                    });
                }
            });

        $normalizedCity = strtoupper(trim((string) $city));
        if ($normalizedCity !== '') {
            $query->whereRaw("upper(btrim(coalesce(u.ciudad, ''))) = ?", [$normalizedCity]);
        }

        return $query;
    }

    private function mapCourierSummary(object $row): array
    {
        $name = trim((string) ($row->name ?? ''));
        $email = trim((string) ($row->email ?? ''));
        $roleName = trim((string) ($row->role_name ?? ''));
        $city = strtoupper(trim((string) ($row->ciudad ?? '')));
        $ci = $this->normalizeCi((string) ($row->ci ?? ''));

        return [
            'id' => (int) ($row->id ?? 0),
            'name' => $name,
            'email' => $email,
            'ci' => $ci,
            'city' => $city,
            'role_name' => $roleName,
            'active_assignments_count' => (int) ($row->active_assignments_count ?? 0),
        ];
    }

    private function resolveCourierForManagementCity(array $authUser, int $targetUserId): array
    {
        $this->ensureCanManageOtherCouriers($authUser);

        if ($targetUserId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar al cartero seleccionado.',
                422,
                'COURIER_REQUIRED',
            );
        }

        $city = $this->authService->isAdministrator($authUser)
            ? null
            : $this->resolveManagementCity($authUser);
        $courier = $this->availableCouriersQueryForCity($city, $authUser)
            ->where('u.id', $targetUserId)
            ->first();

        if ($courier === null) {
            throw new MobileApiException(
                'No encontramos un cartero valido dentro de tu ciudad.',
                404,
                'COURIER_NOT_FOUND',
            );
        }

        return $this->mapCourierSummary($courier);
    }

    private function packageSourceConfigs(): array
    {
        return [
            'ems' => [
                'package_type' => 'ems',
                'table' => 'paquetes_ems',
                'id_column' => 'id',
                'state_columns' => ['estado_id', 'fk_estado', 'estados_id', 'estado'],
                'city_columns' => ['ciudad', 'destino', 'provincia'],
                'recipient_columns' => ['nombre_destinatario', 'destinatario', 'nombre_d'],
                'code_columns' => ['codigo', 'code', 'barcode'],
                'weight_columns' => ['peso'],
                'cartero_foreign_key' => 'id_paquetes_ems',
                'assignable_state_ids' => [
                    self::WAREHOUSE_STATE_ID,
                    self::RECEIVED_STATE_ID,
                    self::DEVOLUTION_STATE_ID,
                ],
            ],
            'certi' => [
                'package_type' => 'certi',
                'table' => 'paquetes_certi',
                'id_column' => 'id',
                'state_columns' => ['fk_estado', 'estado_id', 'estados_id', 'estado'],
                'city_columns' => ['cuidad', 'ciudad', 'destino', 'provincia'],
                'recipient_columns' => ['destinatario', 'nombre_destinatario', 'nombre_d'],
                'code_columns' => ['codigo', 'code', 'barcode'],
                'weight_columns' => ['peso'],
                'cartero_foreign_key' => 'id_paquetes_certi',
                'assignable_state_ids' => [self::WINDOW_STATE_ID, self::DEVOLUTION_STATE_ID],
            ],
            'contrato' => [
                'package_type' => 'contrato',
                'table' => 'paquetes_contrato',
                'id_column' => 'id',
                'state_columns' => ['estados_id', 'estado_id', 'fk_estado', 'estado'],
                'city_columns' => ['destino', 'provincia', 'ciudad'],
                'recipient_columns' => ['nombre_d', 'destinatario', 'nombre_destinatario'],
                'code_columns' => ['codigo', 'code', 'barcode'],
                'weight_columns' => ['peso'],
                'cartero_foreign_key' => 'id_paquetes_contrato',
                'assignable_state_ids' => [
                    self::WAREHOUSE_STATE_ID,
                    self::RECEIVED_STATE_ID,
                    self::DEVOLUTION_STATE_ID,
                ],
            ],
            'ordi' => [
                'package_type' => 'ordi',
                'table' => 'paquetes_ordi',
                'id_column' => 'id',
                'state_columns' => ['fk_estado', 'estado_id', 'estados_id', 'estado'],
                'city_columns' => ['ciudad', 'destino', 'provincia'],
                'recipient_columns' => ['destinatario', 'nombre_destinatario', 'nombre_d'],
                'code_columns' => ['codigo', 'code', 'barcode'],
                'weight_columns' => ['peso'],
                'cartero_foreign_key' => 'id_paquetes_ordi',
                'assignable_state_ids' => [self::WINDOW_STATE_ID, self::DEVOLUTION_STATE_ID],
            ],
        ];
    }

    private function assignableInventoryStateIds(array $config): array
    {
        return array_values(array_unique(array_map(
            static fn (mixed $stateId): int => (int) $stateId,
            $config['assignable_state_ids'] ?? [self::WINDOW_STATE_ID, self::DEVOLUTION_STATE_ID],
        )));
    }

    private function cachedInventoryPackagesForCity(string $city): array
    {
        $signature = $this->inventoryPackagesCacheSignature($city);
        $normalizedCityKey = $this->inventoryPackagesCacheCityKey($city);
        $cacheKey = 'mobile_inventory_packages_'
            .self::INVENTORY_PACKAGES_CACHE_KEY_VERSION
            ."_{$normalizedCityKey}_"
            .sha1("{$city}|{$signature}");

        $cachedPackages = Cache::get($cacheKey);
        if (is_array($cachedPackages)) {
            return $cachedPackages;
        }

        return Cache::lock(
            "{$cacheKey}:rebuild",
            self::INVENTORY_PACKAGES_CACHE_LOCK_SECONDS,
        )->block(self::INVENTORY_PACKAGES_CACHE_LOCK_WAIT_SECONDS, function () use ($cacheKey, $city): array {
            $cachedPackages = Cache::get($cacheKey);
            if (is_array($cachedPackages)) {
                return $cachedPackages;
            }

            $packages = $this->queryAndSortInventoryPackagesForCity($city);
            Cache::put($cacheKey, $packages, self::INVENTORY_PACKAGES_CACHE_TTL_SECONDS);

            return $packages;
        });
    }

    private function inventoryPackagesCacheSignature(string $city): string
    {
        $parts = [];
        foreach ($this->packageSourceConfigs() as $packageType => $config) {
            $parts[] = "{$packageType}:".$this->inventoryPackagesCacheSignatureForConfig($config, $city);
        }

        $parts[] = 'version:'.(int) (Cache::get($this->inventoryPackagesCacheVersionKey($city), 0) ?? 0);

        return implode('|', $parts);
    }

    private function inventoryPackagesCacheSignatureForConfig(array $config, string $city): string
    {
        $tableColumns = $this->getTableColumns($config['table']);
        $stateColumn = $this->pickFirstExistingColumn($tableColumns, $config['state_columns']);
        if ($stateColumn === null) {
            return 'missing-state-column';
        }

        $cityExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['city_columns'],
            fallback: "''",
        );
        $activityExpression = $this->buildInventoryActivityTimestampExpression($tableColumns);
        $activitySelect = $activityExpression === 'null'
            ? 'null'
            : "max({$activityExpression})";

        $row = DB::table("{$config['table']} as p")
            ->selectRaw(
                "count(*) as total, max(p.{$config['id_column']}) as max_id, "
                ."coalesce(sum(p.{$config['id_column']}), 0) as id_sum, "
                ."{$activitySelect} as max_activity_at",
            )
            ->whereIn("p.{$stateColumn}", $this->assignableInventoryStateIds($config))
            ->whereRaw("upper(btrim({$cityExpression})) = ?", [$city])
            ->first();

        return implode(',', [
            'total:'.(int) ($row->total ?? 0),
            'max:'.(int) ($row->max_id ?? 0),
            'sum:'.(string) ($row->id_sum ?? '0'),
            'activity:'.trim((string) ($row->max_activity_at ?? '')),
        ]);
    }

    private function bumpInventoryPackagesCacheVersion(string $city): void
    {
        $key = $this->inventoryPackagesCacheVersionKey($city);
        Cache::add($key, 0);
        Cache::increment($key);
    }

    private function inventoryPackagesCacheVersionKey(string $city): string
    {
        return self::INVENTORY_PACKAGES_CACHE_VERSION_KEY.'_'.$this->inventoryPackagesCacheCityKey($city);
    }

    private function inventoryPackagesCacheCityKey(string $city): string
    {
        $normalized = strtoupper(trim($city));

        return preg_replace('/[^A-Z0-9]+/', '_', $normalized) ?: 'UNKNOWN';
    }

    private function queryAndSortInventoryPackagesForCity(string $city): array
    {
        $packages = [];
        foreach ($this->packageSourceConfigs() as $config) {
            foreach ($this->queryInventoryPackagesForCity($config, $city, $this->assignableInventoryStateIds($config)) as $package) {
                $packages[] = $package;
            }
        }

        usort($packages, static function (array $left, array $right): int {
            $leftDate = trim((string) ($left['created_at'] ?? ''));
            $rightDate = trim((string) ($right['created_at'] ?? ''));

            if ($leftDate !== '' && $rightDate !== '') {
                $dateComparison = strcmp($rightDate, $leftDate);
                if ($dateComparison !== 0) {
                    return $dateComparison;
                }
            } elseif ($leftDate !== '') {
                return -1;
            } elseif ($rightDate !== '') {
                return 1;
            }

            $idComparison = ((int) ($right['package_id'] ?? 0)) <=> ((int) ($left['package_id'] ?? 0));
            if ($idComparison !== 0) {
                return $idComparison;
            }

            return strcmp($left['code'] ?? '', $right['code'] ?? '');
        });

        return $packages;
    }

    private function resolvePackageSourceConfig(string $packageType): array
    {
        $normalizedType = trim(strtolower($packageType));
        $configs = $this->packageSourceConfigs();

        if (! array_key_exists($normalizedType, $configs)) {
            throw new MobileApiException(
                'El servicio seleccionado no es valido para esta asignacion.',
                422,
                'INVALID_PACKAGE_TYPE',
            );
        }

        return $configs[$normalizedType];
    }

    private function queryInventoryPackagesForCity(array $config, string $city, array $visibleStateIds): array
    {
        $tableColumns = $this->getTableColumns($config['table']);
        $stateColumn = $this->pickFirstExistingColumn($tableColumns, $config['state_columns']);
        if ($stateColumn === null) {
            return [];
        }

        $codeExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['code_columns'],
            fallback: "''",
        );
        $cityExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['city_columns'],
            fallback: "''",
        );
        $recipientExpression = $this->buildCoalescedTextExpression(
            alias: 'p',
            availableColumns: $tableColumns,
            preferredColumns: $config['recipient_columns'],
            fallback: "'Sin destinatario'",
        );
        $createdAtExpression = $this->buildInventoryActivityTimestampExpression($tableColumns);

        $rows = DB::table("{$config['table']} as p")
            ->join('estados as pe', 'pe.id', '=', "p.{$stateColumn}")
            ->selectRaw(
                "p.{$config['id_column']} as package_id, '{$config['package_type']}' as package_type, {$codeExpression} as code, {$recipientExpression} as recipient_name, {$cityExpression} as city, {$createdAtExpression} as created_at, pe.nombre_estado as state_name, (SELECT max(coalesce(c.intento, 0)) FROM cartero as c WHERE c.{$config['cartero_foreign_key']} = p.{$config['id_column']}) as attempt_count",
            )
            ->whereIn("p.{$stateColumn}", $visibleStateIds)
            ->whereRaw("upper(btrim({$cityExpression})) = ?", [$city])
            ->whereRaw("nullif(btrim({$codeExpression}), '') is not null")
            ->orderByRaw("{$createdAtExpression} DESC NULLS LAST")
            ->orderByDesc("p.{$config['id_column']}")
            ->get();

        return $rows
            ->map(fn (object $row): ?array => $this->mapInventoryPackageSummary($row))
            ->filter()
            ->values()
            ->all();
    }

    private function mapInventoryPackageSummary(object $row): ?array
    {
        $packageId = (int) ($row->package_id ?? 0);
        $packageType = trim((string) ($row->package_type ?? ''));
        $code = strtoupper(trim((string) ($row->code ?? '')));
        if ($packageId <= 0 || $packageType === '' || $code === '') {
            return null;
        }

        return [
            'package_id' => $packageId,
            'package_type' => $packageType,
            'code' => $code,
            'recipient_name' => trim((string) ($row->recipient_name ?? '')),
            'city' => strtoupper(trim((string) ($row->city ?? ''))),
            'state_name' => strtoupper(trim((string) ($row->state_name ?? self::WINDOW_STATE))),
            'created_at' => $row->created_at instanceof \DateTimeInterface
                ? $row->created_at->format('c')
                : ($row->created_at !== null ? (string) $row->created_at : null),
            'attempt_count' => (int) ($row->attempt_count ?? 0),
        ];
    }

    private function updateAssignedPackageFields(
        int $assignmentId,
        int $courierUserId,
        string $updatedAt,
        ?int $stateId = null,
    ): void {
        $assignment = DB::table('cartero')
            ->select([
                'id_paquetes_ems',
                'id_paquetes_certi',
                'id_paquetes_contrato',
                'id_paquetes_ordi',
            ])
            ->where('id', $assignmentId)
            ->where('id_user', $courierUserId)
            ->lockForUpdate()
            ->first();

        if ($assignment === null) {
            throw new MobileApiException(
                'La asignacion ya no esta activa o no pertenece al cartero actual.',
                409,
                'ASSIGNMENT_NOT_ACTIVE',
            );
        }

        $config = null;
        $packageId = 0;
        foreach ($this->packageSourceConfigs() as $candidateConfig) {
            $candidatePackageId = (int) ($assignment->{$candidateConfig['cartero_foreign_key']} ?? 0);
            if ($candidatePackageId > 0) {
                $config = $candidateConfig;
                $packageId = $candidatePackageId;
                break;
            }
        }

        if ($config === null || $packageId <= 0) {
            throw new MobileApiException(
                'No se pudo identificar el paquete de esta asignacion.',
                409,
                'ASSIGNMENT_PACKAGE_NOT_FOUND',
            );
        }

        $tableColumns = $this->getTableColumns($config['table']);
        $updateValues = [];
        $inventoryCacheCity = null;

        if ($stateId !== null) {
            $stateColumn = $this->pickFirstExistingColumn($tableColumns, $config['state_columns']);
            if ($stateColumn === null) {
                throw new MobileApiException(
                    "La tabla {$config['table']} no tiene una columna de estado compatible.",
                    503,
                    'PACKAGE_STATE_COLUMN_NOT_FOUND',
                );
            }
            $updateValues[$stateColumn] = $stateId;

            $cityExpression = $this->buildCoalescedTextExpression(
                alias: 'p',
                availableColumns: $tableColumns,
                preferredColumns: $config['city_columns'],
                fallback: "''",
            );
            $packageRow = DB::table("{$config['table']} as p")
                ->selectRaw("{$cityExpression} as city")
                ->where("p.{$config['id_column']}", $packageId)
                ->first();
            $inventoryCacheCity = strtoupper(trim((string) ($packageRow->city ?? '')));
        }

        if (in_array('updated_at', $tableColumns, true)) {
            $updateValues['updated_at'] = $updatedAt;
        }

        if ($updateValues === []) {
            return;
        }

        DB::table($config['table'])
            ->where($config['id_column'], $packageId)
            ->update($updateValues);

        if ($inventoryCacheCity !== null && $inventoryCacheCity !== '') {
            DB::afterCommit(function () use ($inventoryCacheCity): void {
                $this->bumpInventoryPackagesCacheVersion($inventoryCacheCity);
            });
        }
    }

    private function normalizeAssignmentStatusName(string $rawStatus): string
    {
        $normalized = strtoupper(trim(str_replace(['-', '_'], ' ', $rawStatus)));
        $compact = preg_replace('/\s+/', ' ', $normalized) ?? '';

        return match ($compact) {
            'ASIGNADO', 'PENDIENTE' => self::ASSIGNED_STATE,
            'CARTERO', 'DOMICILIO', 'EN PROGRESO', 'PROGRESO' => self::IN_PROGRESS_STATE,
            default => throw new MobileApiException(
                'El estado solicitado no es valido para esta asignacion.',
                422,
                'INVALID_ASSIGNMENT_STATUS',
            ),
        };
    }

    private function findStateIdByName(string $stateName): ?int
    {
        $row = DB::table('estados')
            ->select('id')
            ->whereRaw("upper(btrim(coalesce(nombre_estado, ''))) = ?", [strtoupper(trim($stateName))])
            ->where(function ($query): void {
                $query->whereNull('activo')->orWhere('activo', true);
            })
            ->orderBy('id')
            ->first();

        return $row !== null ? (int) ($row->id ?? 0) : null;
    }

    private function resolveStateIdOrFail(string $stateName, string $message, string $errorCode): int
    {
        $stateId = $this->findStateIdByName($stateName);
        if ($stateId === null || $stateId <= 0) {
            throw new MobileApiException($message, 503, $errorCode);
        }

        return $stateId;
    }

    private function buildInventoryActivityTimestampExpression(array $columns): string
    {
        $expressions = [];

        foreach (['updated_at', 'created_at'] as $candidate) {
            if (in_array($candidate, $columns, true)) {
                $expressions[] = "p.{$candidate}";
            }
        }

        if ($expressions === []) {
            return 'null';
        }

        return 'coalesce('.implode(', ', $expressions).')';
    }

    private function buildCoalescedTextExpression(
        string $alias,
        array $availableColumns,
        array $preferredColumns,
        string $fallback,
    ): string {
        $expressions = [];

        foreach ($preferredColumns as $column) {
            if (! in_array($column, $availableColumns, true)) {
                continue;
            }

            $expressions[] = "nullif(btrim(coalesce({$alias}.{$column}::text, '')), '')";
        }

        if ($expressions === []) {
            return $fallback;
        }

        return 'coalesce('.implode(', ', $expressions).", {$fallback})";
    }

    private function resolveDeliveredStateId(): int
    {
        $row = DB::table('estados')
            ->select(['id', 'nombre_estado'])
            ->where('id', self::DELIVERED_STATE_ID)
            ->where(function ($query): void {
                $query->whereNull('activo')->orWhere('activo', true);
            })
            ->first();

        if ($row === null) {
            throw new MobileApiException(
                'No existe el estado ENTREGADO con id 27 en la base de datos.',
                503,
                'DELIVERED_STATE_NOT_FOUND',
            );
        }

        $normalizedStateName = strtoupper(trim((string) ($row->nombre_estado ?? '')));
        if ($normalizedStateName !== self::DELIVERED_STATE_NAME) {
            throw new MobileApiException(
                sprintf(
                    'El estado con id 27 debe llamarse ENTREGADO y actualmente es %s.',
                    $normalizedStateName === '' ? '(sin nombre)' : $normalizedStateName,
                ),
                503,
                'DELIVERED_STATE_MISMATCH',
            );
        }

        return self::DELIVERED_STATE_ID;
    }

    private function resolveWarehouseStateId(): int
    {
        foreach ([self::WAREHOUSE_STATE, self::LEGACY_INVENTORY_STATE] as $stateName) {
            $stateId = $this->findStateIdByName($stateName);
            if ($stateId !== null && $stateId > 0) {
                return $stateId;
            }
        }

        throw new MobileApiException(
            'No existe el estado ALMACEN en la base de datos.',
            503,
            'INVENTORY_STATE_NOT_FOUND',
        );
    }

    private function currentDatabaseTimestamp(): string
    {
        return now('America/La_Paz')->format(self::DATABASE_TIMESTAMP_FORMAT);
    }

    private function getTableColumns(string $tableName): array
    {
        return $this->schemaInspector->getTableColumns($tableName);
    }

    private function pickFirstExistingColumn(array $columns, array $candidates): ?string
    {
        foreach ($candidates as $candidate) {
            if (in_array($candidate, $columns, true)) {
                return $candidate;
            }
        }

        return null;
    }

    private function storeDeliveryPhoto(int $assignmentId, UploadedFile $deliveryPhoto): string
    {
        return $this->storeDeliveryAttachment(
            assignmentId: $assignmentId,
            uploadedFile: $deliveryPhoto,
            directory: 'delivery-confirmations',
            fileNamePrefix: 'confirmacion_asignacion',
            fallbackExtension: 'jpg',
        );
    }

    private function storeDeliverySignature(int $assignmentId, UploadedFile $deliverySignature): string
    {
        return $this->storeDeliveryAttachment(
            assignmentId: $assignmentId,
            uploadedFile: $deliverySignature,
            directory: 'delivery-signatures',
            fileNamePrefix: 'firma_asignacion',
            fallbackExtension: 'png',
        );
    }

    private function storeDevolutionPhoto(int $assignmentId, UploadedFile $deliveryAttemptPhoto): string
    {
        return $this->storeDeliveryAttachment(
            assignmentId: $assignmentId,
            uploadedFile: $deliveryAttemptPhoto,
            directory: 'delivery-devolutions',
            fileNamePrefix: 'devolucion_asignacion',
            fallbackExtension: 'jpg',
        );
    }

    private function storeDeliveryAttachment(
        int $assignmentId,
        UploadedFile $uploadedFile,
        string $directory,
        string $fileNamePrefix,
        string $fallbackExtension,
    ): string {
        $extension = strtolower($uploadedFile->getClientOriginalExtension());
        if ($extension === '') {
            $extension = $fallbackExtension;
        }

        $fileName = sprintf(
            '%s_%d_%s.%s',
            $fileNamePrefix,
            $assignmentId,
            now('America/La_Paz')->format('Ymd_His_u'),
            $extension,
        );

        Storage::disk('public')->makeDirectory($directory);

        $storedPath = Storage::disk('public')->putFileAs(
            $directory,
            $uploadedFile,
            $fileName,
        );

        if ($storedPath === false) {
            $message = match ($directory) {
                'delivery-signatures' => 'No se pudo guardar la firma de entrega.',
                'delivery-devolutions' => 'No se pudo guardar la foto de devolución.',
                default => 'No se pudo guardar la foto del comprobante.',
            };
            $errorCode = match ($directory) {
                'delivery-signatures' => 'DELIVERY_SIGNATURE_STORE_FAILED',
                'delivery-devolutions' => 'DEVOLUTION_PHOTO_STORE_FAILED',
                default => 'DELIVERY_PHOTO_STORE_FAILED',
            };

            throw new MobileApiException(
                $message,
                503,
                $errorCode,
            );
        }

        return $storedPath;
    }

    private function deleteStoredDeliveryEvidence(string ...$paths): void
    {
        $filteredPaths = array_values(array_filter($paths, static fn ($path): bool => trim($path) !== ''));
        if ($filteredPaths === []) {
            return;
        }

        Storage::disk('public')->delete($filteredPaths);
    }

    private static function assignmentsSql(): string
    {
        return <<<'SQL'
WITH assignments AS (
  SELECT
    c.id AS assignment_id,
    pe.codigo::text AS code,
    'ems'::text AS package_type,
    e.nombre_estado::text AS state_name,
    coalesce(c.updated_at, c.created_at) AS created_at
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN paquetes_ems pe ON pe.id = c.id_paquetes_ems
  WHERE c.id_user = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    pc.codigo::text AS code,
    'certi'::text AS package_type,
    e.nombre_estado::text AS state_name,
    coalesce(c.updated_at, c.created_at) AS created_at
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN paquetes_certi pc ON pc.id = c.id_paquetes_certi
  WHERE c.id_user = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    pco.codigo::text AS code,
    'contrato'::text AS package_type,
    e.nombre_estado::text AS state_name,
    coalesce(c.updated_at, c.created_at) AS created_at
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN paquetes_contrato pco ON pco.id = c.id_paquetes_contrato
  WHERE c.id_user = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    po.codigo::text AS code,
    'ordi'::text AS package_type,
    e.nombre_estado::text AS state_name,
    coalesce(c.updated_at, c.created_at) AS created_at
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN paquetes_ordi po ON po.id = c.id_paquetes_ordi
  WHERE c.id_user = ?
),
filtered AS (
  SELECT
    assignment_id,
    upper(btrim(coalesce(code, ''))) AS code,
    package_type,
    btrim(coalesce(state_name, '')) AS state_name,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY upper(btrim(coalesce(code, ''))), package_type
      ORDER BY created_at DESC NULLS LAST, assignment_id DESC
    ) AS row_number
  FROM assignments
  WHERE nullif(btrim(coalesce(code, '')), '') IS NOT NULL
    AND upper(btrim(coalesce(state_name, ''))) IN (
      'ASIGNADO',
      'CARTERO',
      'DOMICILIO'
    )
)
SELECT
  assignment_id,
  code,
  package_type,
  state_name,
  created_at
FROM filtered
WHERE row_number = 1
ORDER BY created_at DESC NULLS LAST, assignment_id DESC, code ASC
SQL;
    }

    private static function regionalRecentAssignedSql(): string
    {
        return <<<'SQL'
WITH assignments AS (
  SELECT
    c.id AS assignment_id,
    pe.codigo::text AS code,
    'ems'::text AS package_type,
    e.nombre_estado::text AS state_name,
    c.created_at AS created_at,
    coalesce(c.updated_at, c.created_at) AS activity_at,
    u.id AS courier_user_id,
    u.name::text AS courier_name
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN users u ON u.id = c.id_user
  JOIN paquetes_ems pe ON pe.id = c.id_paquetes_ems
  WHERE upper(btrim(coalesce(u.ciudad, ''))) = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    pc.codigo::text AS code,
    'certi'::text AS package_type,
    e.nombre_estado::text AS state_name,
    c.created_at AS created_at,
    coalesce(c.updated_at, c.created_at) AS activity_at,
    u.id AS courier_user_id,
    u.name::text AS courier_name
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN users u ON u.id = c.id_user
  JOIN paquetes_certi pc ON pc.id = c.id_paquetes_certi
  WHERE upper(btrim(coalesce(u.ciudad, ''))) = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    pco.codigo::text AS code,
    'contrato'::text AS package_type,
    e.nombre_estado::text AS state_name,
    c.created_at AS created_at,
    coalesce(c.updated_at, c.created_at) AS activity_at,
    u.id AS courier_user_id,
    u.name::text AS courier_name
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN users u ON u.id = c.id_user
  JOIN paquetes_contrato pco ON pco.id = c.id_paquetes_contrato
  WHERE upper(btrim(coalesce(u.ciudad, ''))) = ?

  UNION ALL

  SELECT
    c.id AS assignment_id,
    po.codigo::text AS code,
    'ordi'::text AS package_type,
    e.nombre_estado::text AS state_name,
    c.created_at AS created_at,
    coalesce(c.updated_at, c.created_at) AS activity_at,
    u.id AS courier_user_id,
    u.name::text AS courier_name
  FROM cartero c
  JOIN estados e ON e.id = c.id_estados
  JOIN users u ON u.id = c.id_user
  JOIN paquetes_ordi po ON po.id = c.id_paquetes_ordi
  WHERE upper(btrim(coalesce(u.ciudad, ''))) = ?
)
SELECT
  assignment_id,
  upper(btrim(coalesce(code, ''))) AS code,
  package_type,
  btrim(coalesce(state_name, '')) AS state_name,
  created_at,
  activity_at,
  courier_user_id,
  courier_name
FROM assignments
WHERE nullif(btrim(coalesce(code, '')), '') IS NOT NULL
  AND upper(btrim(coalesce(state_name, ''))) IN (
    'ASIGNADO',
    'CARTERO',
    'DOMICILIO'
  )
  AND activity_at >= ?
  AND activity_at < ?
ORDER BY activity_at DESC NULLS LAST, assignment_id DESC, code ASC
LIMIT 500
SQL;
    }
}
