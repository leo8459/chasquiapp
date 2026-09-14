# Backend ScanAGBC

API Laravel usada por la aplicación móvil ScanAGBC.

## Punto clave

El inicio de sesion no consulta PostgreSQL: el backend autentica contra la API de integracion SIOP y conserva una sesion movil temporal.

PostgreSQL no se levanta con Docker desde este proyecto. Las operaciones postales que aun no tienen una API externa disponible siguen usando la conexion existente.

La API se conecta a un PostgreSQL existente mediante los valores configurados en `.env`.

Docker es opcional y solo sirve para levantar Redis local.

## Instalación

```powershell
composer install

Copy-Item .env.example .env

php artisan key:generate

notepad .env
```

Configura PostgreSQL:

```env
DB_CONNECTION=pgsql
DB_HOST=IP_DEL_SERVIDOR_POSTGRES
DB_PORT=5432
DB_DATABASE=scan_agbc
DB_USERNAME=USUARIO_POSTGRES
DB_PASSWORD=PASSWORD_POSTGRES
DB_SSLMODE=prefer
```

Configura la integracion de inicio de sesion SIOP (el token solo debe existir en el servidor, nunca en Flutter):

```env
SIOP_LOGIN_URL=https://dev.correos.gob.bo:18100/api/integraciones/siop/login
SIOP_LOGIN_TOKEN=TOKEN_DE_INTEGRACION
SIOP_LOGIN_TIMEOUT=15
SIOP_LOGIN_VERIFY_SSL=true
```

Las demás integraciones SIOP siguen el mismo criterio: sus URL y tokens se
configuran exclusivamente en `.env`; también puedes ajustar allí los timeouts
y la verificación SSL. Revisa el bloque `SIOP_*` de `.env.example`: el código
no contiene una URL alternativa.

Para probar sin Docker y sin Redis:

```env
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
```

Levantar API:

```powershell
php artisan config:clear
php artisan cache:clear

php artisan serve --host=0.0.0.0 --port=8001
```

Verificación:

```powershell
curl http://127.0.0.1:8001/api/health
```

## PostgreSQL

La base de datos debe existir en el servidor.

Este proyecto no debe crear, borrar ni migrar automáticamente la base de datos del servidor.

Para verificar conexión de red:

```powershell
Test-NetConnection IP_DEL_SERVIDOR_POSTGRES -Port 5432
```

## Redis

Redis es opcional.

### Sin Redis

Recomendado para pruebas:

```env
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
```

### Redis con Docker

Solo si Docker Desktop está instalado:

```powershell
docker compose up -d
```

Configura `.env`:

```env
SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis

REDIS_CLIENT=predis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=null
```

Luego:

```powershell
php artisan config:clear
php artisan cache:clear
```

### Redis remoto

```env
SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis

REDIS_CLIENT=predis
REDIS_HOST=IP_DEL_SERVIDOR_REDIS
REDIS_PORT=6379
REDIS_PASSWORD=PASSWORD_REDIS
```

## No ejecutar en producción

En una base con datos reales no ejecutes:

```powershell
php artisan migrate
php artisan migrate:fresh
php artisan migrate:refresh
php artisan migrate:reset
php artisan db:wipe
```

El archivo `database/setup/01_schema_scan_agbc.sql` es solo referencia técnica para una instalación nueva y vacía.

## Errores comunes

### `vendor/autoload.php` no existe

Faltan dependencias:

```powershell
composer install
```

### `No application encryption key has been specified`

Falta la clave de Laravel:

```powershell
php artisan key:generate
```

### Cambiaste `.env` y Laravel no toma los cambios

```powershell
php artisan config:clear
php artisan cache:clear
```

## Seguridad

No subir `.env`, contraseñas reales, tokens, certificados, `vendor/`, logs ni cachés.
