# Setup de base de datos

Esta carpeta contiene el esquema PostgreSQL mínimo como referencia técnica para ScanAGBC.

## Importante

La aplicación no debe crear ni modificar automáticamente el PostgreSQL del servidor.

El archivo `01_schema_scan_agbc.sql` solo debe ejecutarse en una base nueva y vacía, con autorización, respaldo y revisión técnica previa.

Configura `backend/.env` con la conexión real del servidor:

```env
DB_CONNECTION=pgsql
DB_HOST=IP_DEL_SERVIDOR_POSTGRES
DB_PORT=5432
DB_DATABASE=scan_agbc
DB_USERNAME=USUARIO_POSTGRES
DB_PASSWORD=PASSWORD_POSTGRES
```

## Advertencia para producción

No ejecutes migraciones automáticamente en producción ni sobre una base con datos reales.

Evita estos comandos en producción:

```powershell
php artisan migrate
php artisan migrate:fresh
php artisan migrate:refresh
php artisan migrate:reset
php artisan db:wipe
```

El script crea estructura base, estados, roles y una ventanilla inicial. No crea usuarios ni contraseñas.

Antes de modificar una base productiva, realiza respaldo y revisión técnica del esquema.
