<?php

namespace App\Services\Seguimiento;

use App\Exceptions\MobileApiException;
use App\Support\Database\PublicSchemaInspector;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class TrackingLookupService
{
    public function __construct(
        private readonly PublicSchemaInspector $schemaInspector,
    ) {}

    public function findByCode(
        string $rawCode,
        bool $includeOperationalDetails = true,
    ): array {
        $normalizedCode = $this->normalizeCode($rawCode);

        if ($normalizedCode === '') {
            throw new MobileApiException(
                'Debes enviar un codigo valido.',
                422,
                'TRACKING_CODE_REQUIRED',
            );
        }

        foreach ($this->resolveSearchOrder($normalizedCode) as $category) {
            $payload = $this->findInCategory(
                $category,
                $normalizedCode,
                $includeOperationalDetails,
            );
            if ($payload !== null) {
                return $payload;
            }
        }

        return [
            'found' => false,
            'code' => $normalizedCode,
        ];
    }

    private function findInCategory(
        string $category,
        string $normalizedCode,
        bool $includeOperationalDetails,
    ): ?array {
        $config = $this->categoryConfig($category);
        $tableName = $config['table'];
        $idColumn = $config['id_column'];
        $carteroForeignKey = $config['cartero_foreign_key'];
        $columns = $this->getTableColumns($tableName);

        if ($columns === [] || ! in_array('codigo', $columns, true) || ! in_array($idColumn, $columns, true)) {
            return null;
        }

        $highlightLocationExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['location_columns'],
            fallback: "''",
        );
        $hasRealLocationExpr = $this->buildHasValueExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['location_columns'],
        );
        $cityExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['city_columns'],
            fallback: "'Sin dato'",
        );
        $provinceExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['province_columns'],
            fallback: "''",
        );
        $recipientExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['recipient_columns'],
            fallback: "'Sin destinatario'",
        );
        $phoneExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['phone_columns'],
            fallback: "'Sin telefono'",
        );
        $weightExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['weight_columns'],
            fallback: "'Sin peso'",
        );
        $detailExpr = $this->buildCoalescedTextExpression(
            alias: 't',
            availableColumns: $columns,
            preferredColumns: $config['detail_columns'],
            fallback: "'Sin contenido o tipo'",
        );
        $stateNameExpr = $includeOperationalDetails
            ? <<<SQL
                (
                  SELECT e.nombre_estado::text
                  FROM public.cartero c
                  JOIN public.estados e ON e.id = c.id_estados
                  WHERE c.{$carteroForeignKey} = t.{$idColumn}
                  ORDER BY c.updated_at DESC NULLS LAST, c.id DESC
                  LIMIT 1
                )
                SQL
            : 'NULL::text';
        $attemptCountExpr = $includeOperationalDetails
            ? <<<SQL
                (
                  SELECT coalesce(c.intento, 0)
                  FROM public.cartero c
                  WHERE c.{$carteroForeignKey} = t.{$idColumn}
                  ORDER BY c.updated_at DESC NULLS LAST, c.id DESC
                  LIMIT 1
                )
                SQL
            : '0';
        $assignedCourierNameExpr = $includeOperationalDetails
            ? <<<SQL
                (
                  SELECT u.name::text
                  FROM public.cartero c
                  JOIN public.estados e ON e.id = c.id_estados
                  JOIN public.users u ON u.id = c.id_user
                  WHERE c.{$carteroForeignKey} = t.{$idColumn}
                    AND upper(btrim(coalesce(e.nombre_estado, ''))) IN ('ASIGNADO', 'CARTERO', 'DOMICILIO')
                  ORDER BY c.updated_at DESC NULLS LAST, c.id DESC
                  LIMIT 1
                )
                SQL
            : 'NULL::text';
        $orderColumn = $this->resolveOrderColumn($columns);

        $row = DB::selectOne(
            <<<SQL
            SELECT
              t.{$idColumn} AS package_id,
              {$highlightLocationExpr} AS highlight_location,
              CASE
                WHEN {$hasRealLocationExpr} THEN NULL
                ELSE 'no contamos con direccion o zona registrada para este paquete'
              END AS location_note,
              {$cityExpr} AS city,
              {$provinceExpr} AS province,
              {$recipientExpr} AS recipient_name,
              {$phoneExpr} AS phone,
              {$weightExpr} AS weight,
              {$detailExpr} AS detail,
              {$stateNameExpr} AS state_name,
              {$attemptCountExpr} AS attempt_count,
              {$assignedCourierNameExpr} AS assigned_courier_name
            FROM public.{$tableName} t
            WHERE upper(t.codigo::text) = ?
            ORDER BY t.{$orderColumn} ASC
            LIMIT 1
            SQL,
            [$normalizedCode],
        );

        if ($row === null) {
            return null;
        }

        return [
            'found' => true,
            'package_id' => (int) ($row->package_id ?? 0),
            'code' => $normalizedCode,
            'package_type' => $category,
            'highlight_location' => trim((string) ($row->highlight_location ?? '')),
            'location_note' => trim((string) ($row->location_note ?? '')),
            'city' => trim((string) ($row->city ?? '')),
            'province' => trim((string) ($row->province ?? '')),
            'recipient_name' => trim((string) ($row->recipient_name ?? '')),
            'phone' => trim((string) ($row->phone ?? '')),
            'weight' => trim((string) ($row->weight ?? '')),
            'detail' => trim((string) ($row->detail ?? '')),
            'state_name' => strtoupper(trim((string) ($row->state_name ?? ''))),
            'attempt_count' => (int) ($row->attempt_count ?? 0),
            'assigned_courier_name' => trim((string) ($row->assigned_courier_name ?? '')),
        ];
    }

    private function resolveSearchOrder(string $normalizedCode): array
    {
        $ordered = [];

        if ($this->startsWithAny($normalizedCode, ['EA', 'EB', 'EC', 'ED', 'EE', 'EF', 'EG', 'EH', 'EI', 'EJ', 'EK', 'EL', 'EM', 'EN', 'EO', 'EP', 'EQ', 'ER', 'ES', 'ET', 'EU', 'EV', 'EW', 'EX', 'EY', 'EZ', 'AG'])) {
            $ordered[] = 'ems';
        } elseif (str_starts_with($normalizedCode, 'C0')) {
            $ordered[] = 'contrato';
        } elseif ($this->startsWithAny($normalizedCode, ['CP', 'OR', 'U', 'L'])) {
            $ordered[] = 'ordi';
        } elseif (str_starts_with($normalizedCode, 'R')) {
            $ordered[] = 'certi';
        }

        foreach (['ems', 'certi', 'contrato', 'ordi'] as $category) {
            if (! in_array($category, $ordered, true)) {
                $ordered[] = $category;
            }
        }

        return $ordered;
    }

    private function categoryConfig(string $category): array
    {
        return match ($category) {
            'ems' => [
                'table' => 'paquetes_ems',
                'id_column' => 'id',
                'cartero_foreign_key' => 'id_paquetes_ems',
                'location_columns' => ['direccion'],
                'city_columns' => ['ciudad', 'destino', 'provincia'],
                'province_columns' => ['provincia'],
                'recipient_columns' => ['nombre_destinatario'],
                'phone_columns' => ['telefono_destinatario'],
                'weight_columns' => ['peso'],
                'detail_columns' => ['contenido', 'tipo_correspondencia'],
            ],
            'certi' => [
                'table' => 'paquetes_certi',
                'id_column' => 'id',
                'cartero_foreign_key' => 'id_paquetes_certi',
                'location_columns' => ['zona', 'direccion'],
                'city_columns' => ['cuidad', 'ciudad', 'destino', 'provincia'],
                'province_columns' => ['provincia'],
                'recipient_columns' => ['destinatario'],
                'phone_columns' => ['telefono'],
                'weight_columns' => ['peso'],
                'detail_columns' => ['tipo', 'observaciones'],
            ],
            'contrato' => [
                'table' => 'paquetes_contrato',
                'id_column' => 'id',
                'cartero_foreign_key' => 'id_paquetes_contrato',
                'location_columns' => ['direccion_d'],
                'city_columns' => ['destino', 'provincia', 'ciudad'],
                'province_columns' => ['provincia'],
                'recipient_columns' => ['nombre_d'],
                'phone_columns' => ['telefono_d'],
                'weight_columns' => ['peso'],
                'detail_columns' => ['contenido', 'observaciones'],
            ],
            'ordi' => [
                'table' => 'paquetes_ordi',
                'id_column' => 'id',
                'cartero_foreign_key' => 'id_paquetes_ordi',
                'location_columns' => ['zona', 'direccion'],
                'city_columns' => ['ciudad', 'destino', 'provincia'],
                'province_columns' => ['provincia'],
                'recipient_columns' => ['destinatario'],
                'phone_columns' => ['telefono'],
                'weight_columns' => ['peso'],
                'detail_columns' => ['observaciones', 'tipo'],
            ],
            default => throw new RuntimeException("Categoria no soportada: {$category}"),
        };
    }

    private function getTableColumns(string $tableName): array
    {
        return $this->schemaInspector->getTableColumns($tableName);
    }

    private function resolveOrderColumn(array $columns): string
    {
        foreach (['id', 'created_at', 'codigo'] as $candidate) {
            if (in_array($candidate, $columns, true)) {
                return $candidate;
            }
        }

        return 'codigo';
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

    private function buildHasValueExpression(
        string $alias,
        array $availableColumns,
        array $preferredColumns,
    ): string {
        $checks = [];

        foreach ($preferredColumns as $column) {
            if (! in_array($column, $availableColumns, true)) {
                continue;
            }

            $checks[] = "nullif(btrim(coalesce({$alias}.{$column}::text, '')), '') IS NOT NULL";
        }

        if ($checks === []) {
            return 'false';
        }

        return implode(' OR ', $checks);
    }

    private function normalizeCode(string $rawCode): string
    {
        $withoutSpaces = preg_replace('/[^A-Z0-9]+/i', '', $rawCode) ?? '';

        return strtoupper(trim($withoutSpaces));
    }

    private function startsWithAny(string $value, array $prefixes): bool
    {
        foreach ($prefixes as $prefix) {
            if (str_starts_with($value, $prefix)) {
                return true;
            }
        }

        return false;
    }
}
