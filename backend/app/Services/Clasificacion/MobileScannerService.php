<?php

namespace App\Services\Clasificacion;

use App\Exceptions\MobileApiException;
use App\Services\Autenticacion\MobileAuthService;
use App\Support\Database\PublicSchemaInspector;
use Illuminate\Support\Facades\DB;

class MobileScannerService
{
    private const ESTADO_ID = 25;

    private const DEFAULT_VENTANILLA_ID = 1;

    public function __construct(
        private readonly MobileAuthService $authService,
        private readonly PublicSchemaInspector $schemaInspector,
    ) {}

    public function getVentanillas(array $authUser): array
    {
        $this->ensureCanRegisterPackages($authUser);

        $ventanillasTable = $this->schemaInspector->pickExistingTable([
            'ventanillas',
            'ventanilla',
        ]);
        if ($ventanillasTable === null) {
            return [['id' => 1, 'label' => 'Ventanilla 1']];
        }

        $columns = $this->getTableColumns($ventanillasTable);
        $idColumn = in_array('id', $columns, true)
            ? 'id'
            : (in_array('ventanilla_id', $columns, true) ? 'ventanilla_id' : null);

        if ($idColumn === null) {
            return [['id' => 1, 'label' => 'Ventanilla 1']];
        }

        $labelColumn = $this->pickFirstExistingColumn($columns, [
            'nombre_ventanilla',
            'nombre',
            'nombre_vent',
            'name',
            'descripcion',
            'codigo',
        ]);

        $labelExpression = $labelColumn ?? "{$idColumn}::text";
        $rows = DB::table($ventanillasTable)
            ->selectRaw("{$idColumn} AS id, {$labelExpression} AS label")
            ->orderBy($idColumn)
            ->get();

        if ($rows->isEmpty()) {
            return [['id' => 1, 'label' => 'Ventanilla 1']];
        }

        return $rows->map(function (object $row): ?array {
            $id = (int) ($row->id ?? 0);
            if ($id <= 0) {
                return null;
            }

            $label = strtoupper(trim((string) ($row->label ?? '')));

            return [
                'id' => $id,
                'label' => $label !== '' ? $label : "VENTANILLA {$id}",
            ];
        })->filter()->values()->all();
    }

    public function saveScan(array $authUser, array $payload): void
    {
        $this->ensureCanRegisterPackages($authUser);

        $barcodeText = strtoupper(trim((string) ($payload['barcode_text'] ?? '')));
        $codePrefix = $this->barcodePrefix($barcodeText);

        if (! in_array($codePrefix, ['R', 'U', 'L'], true)) {
            throw new MobileApiException(
                'El código escaneado no tiene un formato válido para guardar.',
                422,
                'CODIGO_BARRA_INVALIDO',
            );
        }

        $packageTable = $this->resolveTargetPackageTable($codePrefix);

        if ($packageTable === null) {
            throw new MobileApiException(
                'No existe la tabla destino para este tipo de paquete.',
                503,
                'TABLA_DESTINO_NO_ENCONTRADA',
            );
        }

        $columns = $this->getTableColumns($packageTable);
        $columnTypes = $this->getTableColumnTypes($packageTable);
        $barcodeColumn = $this->pickFirstExistingColumn($columns, ['barcode', 'codigo', 'code']);
        $estadoColumn = $this->pickFirstExistingColumn($columns, ['estado_id', 'fk_estado', 'estado']);

        $normalizedCode = $barcodeText !== '' ? $barcodeText : 'SIN-CODIGO';
        $normalizedDestinatario = $this->normalizedUpperValue($payload['nombre'] ?? '', 'SIN NOMBRE');
        $normalizedTelefonoDigits = preg_replace('/\D/', '', (string) ($payload['telefono'] ?? '')) ?? '';
        $normalizedTelefono = $normalizedTelefonoDigits !== '' ? $normalizedTelefonoDigits : null;
        $normalizedTelefonoValue = $normalizedTelefono ?? '0';
        $normalizedAduana = filter_var($payload['aduana'] ?? false, FILTER_VALIDATE_BOOL) ? 'SI' : 'NO';
        $normalizedZona = trim((string) ($payload['zona'] ?? '')) !== ''
            ? trim((string) $payload['zona'])
            : 'S/N';
        $normalizedPeso = (float) ($payload['peso'] ?? 0);
        if ($normalizedPeso <= 0) {
            $normalizedPeso = 0.001;
        }

        $normalizedVentanillaId = (int) ($payload['ventanilla_id'] ?? self::DEFAULT_VENTANILLA_ID);
        if ($normalizedVentanillaId <= 0) {
            $normalizedVentanillaId = self::DEFAULT_VENTANILLA_ID;
        }

        $normalizedVentanillaNombre = trim((string) ($payload['ventanilla_nombre'] ?? ''));
        $normalizedTipoDocumento = trim((string) ($payload['tipo_documento'] ?? '')) !== ''
            ? trim((string) $payload['tipo_documento'])
            : 'Documento';
        $normalizedObservaciones = strtoupper(trim((string) ($payload['observaciones'] ?? '')));
        $normalizedCiudad = trim((string) ($payload['ciudad'] ?? ''));
        $createdAt = trim((string) ($payload['created_at'] ?? ''));
        $resolvedCreatedAt = $createdAt !== '' ? $createdAt : now()->toIso8601String();

        if (
            $barcodeColumn !== null &&
            $estadoColumn !== null &&
            $this->barcodeExistsWithEstado($packageTable, $barcodeColumn, $estadoColumn, $normalizedCode, self::ESTADO_ID)
        ) {
            throw new MobileApiException(
                'Este paquete ya fue clasificado.',
                409,
                'PAQUETE_YA_CLASIFICADO',
            );
        }

        $sourceValues = [
            'name' => $normalizedDestinatario,
            'nombre' => $normalizedDestinatario,
            'destinatario' => $normalizedDestinatario,
            'destinario' => $normalizedDestinatario,
            'nombre_destinatario' => $normalizedDestinatario,
            'nombre_d' => $normalizedDestinatario,
            'phone' => $normalizedTelefonoValue,
            'telefono' => $normalizedTelefonoValue,
            'telefono_destinatario' => $normalizedTelefonoValue,
            'telefono_d' => $normalizedTelefonoValue,
            'ciudad' => $normalizedCiudad,
            'city' => $normalizedCiudad,
            'cuidad' => $normalizedCiudad,
            'destino' => $normalizedCiudad,
            'provincia' => $normalizedCiudad,
            'zona' => $normalizedZona,
            'direccion' => $normalizedZona,
            'direccion_d' => $normalizedZona,
            'zone' => $normalizedZona,
            'peso' => $normalizedPeso,
            'weight' => $normalizedPeso,
            'aduana' => $normalizedAduana,
            'customs' => $normalizedAduana,
            'code' => $normalizedCode,
            'codigo' => $normalizedCode,
            'barcode' => $normalizedCode,
            'estado' => self::ESTADO_ID,
            'estado_id' => self::ESTADO_ID,
            'fk_estado' => self::ESTADO_ID,
            'ventanilla_id' => $normalizedVentanillaId,
            'fk_ventanilla' => $normalizedVentanillaId,
            'ventanilla' => $normalizedVentanillaNombre !== ''
                ? $normalizedVentanillaNombre
                : (string) $normalizedVentanillaId,
            'tipo' => $normalizedTipoDocumento,
            'contenido' => $normalizedTipoDocumento,
            'tipo_correspondencia' => $normalizedTipoDocumento,
            'observacione' => $normalizedObservaciones,
            'observaciones' => $normalizedObservaciones,
            'observacion' => $normalizedObservaciones,
            'created_at' => $resolvedCreatedAt,
            'updated_at' => $resolvedCreatedAt,
            'fecha_registro' => $resolvedCreatedAt,
        ];

        if ($normalizedTelefono !== null) {
            $sourceValues['telefono_numerico'] = (int) $normalizedTelefono;
        }

        $values = [];
        foreach ($columns as $column) {
            if (! array_key_exists($column, $sourceValues)) {
                continue;
            }

            $value = $sourceValues[$column];
            if (
                in_array($column, ['telefono', 'telefono_destinatario', 'telefono_d'], true) &&
                $this->isIntegerColumnType($columnTypes[$column] ?? '')
            ) {
                $value = $this->normalizePhoneForIntegerColumn($normalizedTelefono);
            }

            $values[$column] = $value;
        }

        if ($values === []) {
            DB::statement("INSERT INTO {$packageTable} DEFAULT VALUES");

            return;
        }

        DB::table($packageTable)->insert($values);
    }

    private function ensureCanRegisterPackages(array $authUser): void
    {
        if (! $this->authService->canRegisterPackages($authUser)) {
            throw new MobileApiException(
                'No tienes permisos para registrar paquetes.',
                403,
                'FORBIDDEN_SCAN_REGISTRATION',
            );
        }
    }

    private function barcodePrefix(string $barcodeText): string
    {
        return $barcodeText === '' ? '' : substr($barcodeText, 0, 1);
    }

    private function normalizedUpperValue(mixed $value, string $fallback): string
    {
        $normalized = strtoupper(trim((string) $value));

        return $normalized !== '' ? $normalized : $fallback;
    }

    private function getTableColumns(string $tableName): array
    {
        return $this->schemaInspector->getTableColumns($tableName);
    }

    private function getTableColumnTypes(string $tableName): array
    {
        return $this->schemaInspector->getTableColumnTypes($tableName);
    }

    private function resolveTargetPackageTable(string $codePrefix): ?string
    {
        if ($codePrefix === 'R') {
            return $this->schemaInspector->pickExistingTable([
                'paquetes_certi',
                'paquete_certi',
                'certi',
            ]);
        }

        if (in_array($codePrefix, ['U', 'L'], true)) {
            return $this->schemaInspector->pickExistingTable([
                'paquetes_ordi',
                'paquete_ordi',
                'ordi',
            ]);
        }

        return null;
    }

    private function pickFirstExistingColumn(array $columns, array $options): ?string
    {
        foreach ($options as $name) {
            if (in_array($name, $columns, true)) {
                return $name;
            }
        }

        return null;
    }

    private function isIntegerColumnType(string $dataType): bool
    {
        return in_array($dataType, ['integer', 'smallint', 'bigint'], true);
    }

    private function normalizePhoneForIntegerColumn(?string $digits): ?int
    {
        if ($digits === null || $digits === '') {
            return null;
        }

        $normalized = $digits;
        if (strlen($normalized) > 8) {
            $normalized = substr($normalized, -8);
        }

        return (int) $normalized;
    }

    private function barcodeExistsWithEstado(
        string $table,
        string $barcodeColumn,
        string $estadoColumn,
        string $barcode,
        int $estadoId,
    ): bool {
        if ($barcode === '') {
            return false;
        }

        return DB::table($table)
            ->where($barcodeColumn, $barcode)
            ->where($estadoColumn, $estadoId)
            ->exists();
    }
}
