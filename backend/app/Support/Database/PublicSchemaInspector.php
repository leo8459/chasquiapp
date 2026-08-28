<?php

namespace App\Support\Database;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class PublicSchemaInspector
{
    private const CACHE_TTL_MINUTES = 15;

    private ?array $publicTableNames = null;

    private array $tableColumns = [];

    private array $tableColumnTypes = [];

    public function getPublicTableNames(): array
    {
        if ($this->publicTableNames !== null) {
            return $this->publicTableNames;
        }

        return $this->publicTableNames = Cache::remember(
            'mobile_api_schema:public_tables',
            now()->addMinutes(self::CACHE_TTL_MINUTES),
            function (): array {
                $rows = DB::select(
                    <<<'SQL'
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_type = 'BASE TABLE'
                    SQL,
                );

                return array_values(array_filter(array_map(
                    fn (object $row): string => trim((string) ($row->table_name ?? '')),
                    $rows,
                )));
            },
        );
    }

    public function getTableColumns(string $tableName): array
    {
        if (array_key_exists($tableName, $this->tableColumns)) {
            return $this->tableColumns[$tableName];
        }

        return $this->tableColumns[$tableName] = Cache::remember(
            "mobile_api_schema:columns:{$tableName}",
            now()->addMinutes(self::CACHE_TTL_MINUTES),
            function () use ($tableName): array {
                if (! Schema::hasTable($tableName)) {
                    return [];
                }

                return Schema::getColumnListing($tableName);
            },
        );
    }

    public function getTableColumnTypes(string $tableName): array
    {
        if (array_key_exists($tableName, $this->tableColumnTypes)) {
            return $this->tableColumnTypes[$tableName];
        }

        return $this->tableColumnTypes[$tableName] = Cache::remember(
            "mobile_api_schema:column_types:{$tableName}",
            now()->addMinutes(self::CACHE_TTL_MINUTES),
            function () use ($tableName): array {
                if (! Schema::hasTable($tableName)) {
                    return [];
                }

                $rows = DB::select(
                    <<<'SQL'
                    SELECT column_name, data_type
                    FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = ?
                    SQL,
                    [$tableName],
                );

                $types = [];
                foreach ($rows as $row) {
                    $column = trim((string) ($row->column_name ?? ''));
                    $dataType = trim((string) ($row->data_type ?? ''));
                    if ($column === '') {
                        continue;
                    }

                    $types[$column] = $dataType;
                }

                return $types;
            },
        );
    }

    public function pickExistingTable(array $options): ?string
    {
        $existingTables = $this->getPublicTableNames();

        foreach ($options as $name) {
            if (in_array($name, $existingTables, true)) {
                return $name;
            }
        }

        return null;
    }
}
