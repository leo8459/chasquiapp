# Instalación en este servidor

La API usa PHP-FPM 8.2 y Nginx en contenedores independientes, con reinicio
automático. Dirección interna: `http://172.65.10.56:8001/api`.
Dirección pública HTTPS: `https://dev.correos.gob.bo:18100/chasquiapp/api`.

El Nginx existente de `bolipost_app` publica `/chasquiapp/` mediante un proxy
a `172.65.10.56:8001`, quitando ese prefijo. Su configuración persistente está
en `/home/agbc/bolipost/docker/nginx.conf`. Las otras rutas de ese servidor
conservan su comportamiento. Nginx se validó antes de recargarlo.

Descarga Android: `https://dev.correos.gob.bo:18100/chasquiapp/descargas/`.
El APK se publica en `public/descargas/chasquiapp.apk` y queda excluido de Git.
El teléfono muestra el nombre `ChasquiApp`, definido por el proyecto Android.

La app consulta `GET /api/mobile/app-version` al iniciar y al volver al primer
plano. El enlace del APK se arma con `APP_URL` de cada instalación; configura
ese valor con su dominio público y el prefijo `/chasquiapp`. Por ejemplo,
`https://dev.correos.gob.bo:18100/chasquiapp` o
`https://trackingbo.correos.gob.bo:8100/chasquiapp`. Deja
`MOBILE_DOWNLOAD_URL` vacío para usar ese enlace automáticamente, o asígnalo
solo si necesitas una dirección fija distinta. Para exigir una actualización,
sube el APK nuevo conservando la
misma clave de firma y aumenta `MOBILE_MINIMUM_VERSION` a la versión de
`pubspec.yaml`; luego ejecuta `php artisan config:cache` y reinicia PHP-FPM.
El bloqueo requiere conexión al servidor.

El archivo privado `backend/.env` contiene la configuración de producción.
PostgreSQL es el existente en `172.65.10.56:5432`; este despliegue no ejecuta
migraciones ni crea una base de datos. Caché y sesiones usan archivos y las
colas se ejecutan de forma síncrona, por lo que Redis no es necesario.

Desde `backend/`:

```bash
docker compose -f compose.server.yml up -d
docker compose -f compose.server.yml ps
docker compose -f compose.server.yml logs --tail=100
curl --fail http://172.65.10.56:8001/api/health
```

Después de cambiar `.env`:

```bash
docker compose -f compose.server.yml exec -T app php artisan config:cache
chmod 600 bootstrap/cache/config.php
docker compose -f compose.server.yml restart app
```

La imagen local `bolipost-app:latest` proporciona PHP, Composer y las
extensiones, incluida `pdo_pgsql`. Se reutiliza en un contenedor separado,
con la aplicación de este repositorio montada en `/app` y una configuración
PHP-FPM propia. Esta imagen debe existir si se traslada el despliegue.
Los procesos PHP usan UID/GID `1000:1000`, correspondientes al propietario
del proyecto en este servidor. Solo `storage` y `bootstrap/cache` se montan
con escritura en el servicio PHP.

Se instalaron las dependencias de `composer.lock` con `--no-dev` y autoload
optimizado. La compilación móvil usa Flutter 3.41.0 y Android SDK dentro de
Docker, con una copia del código móvil en `/tmp/chasqui-android-build`, sin
montar el backend ni su `.env`. El APK se compila con
`--dart-define-from-file=.env`, usando `API_BASE_URL` del archivo privado de
configuración de Flutter ubicado en la raíz del proyecto.
El proyecto utiliza su configuración de firma Android existente (`debug`
para el modo release); la clave se conserva fuera del directorio público,
en `build/android-signing`, para mantener la firma en futuras compilaciones.

## Integraciones SIOP

Los tokens SIOP proporcionados están configurados en el archivo privado
`backend/.env`. Se conserva la conexión PostgreSQL existente. La configuración
publicada usa `APP_ENV=production`, `APP_DEBUG=false` y la URL del servidor.

Las URL SIOP se leen de las variables `SIOP_*_URL` de `backend/.env`. Para
trasladar el sistema, deben actualizarse allí las URL de cada operación.
Las URL `TRACKING_SQLSERVER_*` y `TRACKING_API_URL` conservan los destinos
proporcionados. `APP_URL` usa la dirección pública HTTPS con `/chasquiapp`.
Este backend no implementa una ruta
de autenticación Google; esa variable se conservó del entorno proporcionado.

Verificado: requisitos PHP de producción, caché de configuración y rutas,
respuesta de `/api/health` y conexión PostgreSQL mediante `SELECT 1`.
Además, se comprobó la respuesta HTTPS de `/chasquiapp/api/health` y la
validación de campos obligatorios del inicio de sesión, tanto en la app como
en SIOP usando el token de integración. No se probó una sesión con usuario
real ni las operaciones postales de extremo a extremo.
