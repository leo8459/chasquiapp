# ScanAGBC

Aplicación móvil Flutter con backend Laravel para operaciones postales. Incluye autenticación por rol, seguimiento de paquetes, clasificación, gestión de asignaciones y registro de entregas/devoluciones por carteros.

## Importante antes de ejecutar

Este proyecto no levanta PostgreSQL con Docker.

La base de datos PostgreSQL vive en un servidor externo y la aplicación solo se conecta usando IP, puerto, nombre de base de datos, usuario y contraseña configurados en `backend/.env`.

Docker es opcional y solo se usa para Redis.

## Requisitos

- Flutter y Dart.
- Android SDK.
- PHP 8.2 o superior.
- Composer.
- Acceso al servidor PostgreSQL.
- Redis opcional.
- Docker Desktop opcional, solo si quieres levantar Redis localmente.

## Estructura

```text
ScanAGBC/
├── android/        Proyecto Android de Flutter
├── assets/         Recursos de la aplicación
├── lib/            Código fuente Flutter
├── backend/        API Laravel
├── pubspec.yaml    Dependencias Flutter
└── README.md
```

## Instalación rápida sin Docker

Esta es la forma recomendada para probar localmente.

### 1. Preparar backend

Desde la raíz del proyecto:

```powershell
cd backend

composer install

Copy-Item .env.example .env

php artisan key:generate

notepad .env
```

En `backend/.env` configura tus datos reales de PostgreSQL:

```env
APP_URL=http://127.0.0.1:8001

DB_CONNECTION=pgsql
DB_HOST=IP_DEL_SERVIDOR_POSTGRES
DB_PORT=5432
DB_DATABASE=scan_agbc
DB_USERNAME=USUARIO_POSTGRES
DB_PASSWORD=PASSWORD_POSTGRES
```

Para probar sin Redis y sin Docker deja estos valores:

```env
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
```

Luego levanta la API:

```powershell
php artisan config:clear
php artisan cache:clear

php artisan serve --host=0.0.0.0 --port=8001
```

Verifica que la API responda:

```powershell
curl http://127.0.0.1:8001/api/health
```

### 2. Ejecutar Flutter

En otra terminal, desde la raíz del proyecto:

```powershell
flutter pub get
```

Para teléfono físico en la misma red Wi-Fi:

```powershell
Copy-Item .env.example .env
notepad .env
flutter run -d 21121119SG --dart-define-from-file=.env
```

Ejemplo si la IP de tu PC fuera `192.168.1.50`:

```powershell
# .env
API_BASE_URL=http://192.168.1.50:8001/api

flutter run -d 21121119SG --dart-define-from-file=.env
```

Para emulador Android:

```powershell
# .env
API_BASE_URL=http://10.0.2.2:8001/api

flutter run --dart-define-from-file=.env
```

Para obtener la IP de tu PC:

```powershell
ipconfig
```

Busca la dirección IPv4 de tu adaptador Wi-Fi o Ethernet.

## Configuración de PostgreSQL

PostgreSQL debe estar creado y disponible en el servidor.

El proyecto no debe crear, borrar ni migrar la base automáticamente.

Configura la conexión en `backend/.env`:

```env
DB_CONNECTION=pgsql
DB_HOST=IP_DEL_SERVIDOR_POSTGRES
DB_PORT=5432
DB_DATABASE=scan_agbc
DB_USERNAME=USUARIO_POSTGRES
DB_PASSWORD=PASSWORD_POSTGRES
DB_SSLMODE=prefer
```

Para comprobar si tu PC puede llegar al servidor PostgreSQL:

```powershell
Test-NetConnection IP_DEL_SERVIDOR_POSTGRES -Port 5432
```

Si aparece:

```text
TcpTestSucceeded : True
```

la conexión de red al puerto PostgreSQL está disponible.

## No ejecutar migraciones en producción

En una base con datos reales no ejecutes:

```powershell
php artisan migrate
php artisan migrate:fresh
php artisan migrate:refresh
php artisan migrate:reset
php artisan db:wipe
```

El archivo `backend/database/setup/01_schema_scan_agbc.sql` queda como referencia técnica para una instalación nueva y vacía. No lo ejecutes sobre la base del servidor sin autorización, respaldo y revisión técnica.

## Redis

Redis es opcional para pruebas locales.

Redis puede usarse para sesiones, caché y colas. Si no quieres instalar Docker ni Redis, usa el modo simple con archivos locales.

### Opción A: sin Redis

Recomendado para probar rápido.

En `backend/.env`:

```env
SESSION_DRIVER=file
CACHE_STORE=file
QUEUE_CONNECTION=sync
```

Después limpia configuración:

```powershell
cd backend

php artisan config:clear
php artisan cache:clear
```

### Opción B: Redis local con Docker

Solo si tienes Docker Desktop instalado.

Desde `backend/`:

```powershell
docker compose up -d
```

Luego en `backend/.env`:

```env
SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis

REDIS_CLIENT=predis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=null
```

Limpia configuración:

```powershell
php artisan config:clear
php artisan cache:clear
```

### Opción C: Redis remoto

Si Redis está en otro servidor:

```env
SESSION_DRIVER=redis
CACHE_STORE=redis
QUEUE_CONNECTION=redis

REDIS_CLIENT=predis
REDIS_HOST=IP_DEL_SERVIDOR_REDIS
REDIS_PORT=6379
REDIS_PASSWORD=PASSWORD_REDIS
```

Si Redis no tiene contraseña:

```env
REDIS_PASSWORD=null
```

## APK release

```powershell
flutter build apk --release --split-per-abi --dart-define-from-file=.env
```

La URL queda incorporada al APK durante la compilación. Para publicar en otro
servidor, actualiza `API_BASE_URL` en `.env` y vuelve a compilar el APK.

## Errores comunes

### Falta `vendor/autoload.php`

Ejecuta:

```powershell
cd backend
composer install
```

### Falta `APP_KEY`

Ejecuta:

```powershell
cd backend
php artisan key:generate
```

### Laravel sigue leyendo configuración antigua

Ejecuta:

```powershell
cd backend
php artisan config:clear
php artisan cache:clear
```

### El teléfono no entra a la API

Revisa:

- El teléfono y la PC deben estar en la misma red.
- Usa la IP real de la PC, no `127.0.0.1`.
- El backend debe estar levantado con `--host=0.0.0.0`.
- El firewall de Windows debe permitir el puerto `8001`.

## Seguridad para GitHub

No subir:

- `backend/.env`
- tokens o claves privadas
- contraseñas reales
- certificados, keystores, `.jks`, `.p12`
- `backend/vendor/`
- `build/`
- `.dart_tool/`
- logs y cachés

El archivo público correcto es:

```text
backend/.env.example
```

## Subir a GitHub

```powershell
git add .
git commit -m "Preparar ScanAGBC"
git remote add origin https://github.com/vismarkchoquecachi/ScanAGBC.git
git push -u origin main
```
