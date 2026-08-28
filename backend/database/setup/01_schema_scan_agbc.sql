-- ============================================================================
-- ScanAGBC
-- Script SQL referencial de estructura PostgreSQL
-- ============================================================================
-- Uso:
--   Este script documenta una estructura mínima compatible con los módulos
--   móviles revisados: autenticación, roles, paquetes, cartero, estados,
--   ventanillas y eventos.
--
-- Advertencia:
--   No ejecutar sobre producción sin respaldo, revisión del DBA y comparación
--   con la base operativa real. El proyecto trabaja con una base existente y
--   el backend inspecciona columnas dinámicamente para soportar variantes.
-- ============================================================================

/*
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    email_verified_at TIMESTAMP NULL,
    password VARCHAR(255) NOT NULL,
    ciudad VARCHAR(120) NULL,
    ci VARCHAR(40) NULL,
    remember_token VARCHAR(100) NULL,
    deleted_at TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS roles (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    guard_name VARCHAR(255) NOT NULL DEFAULT 'web',
    nombre VARCHAR(255) NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (name, guard_name)
);

INSERT INTO roles (name, guard_name, nombre)
VALUES
    ('administrador', 'web', 'Administrador'),
    ('gestion', 'web', 'Gestión'),
    ('cartero', 'web', 'Cartero'),
    ('clasificacion', 'web', 'Clasificación')
ON CONFLICT (name, guard_name) DO UPDATE
SET nombre = EXCLUDED.nombre,
    updated_at = CURRENT_TIMESTAMP;

CREATE TABLE IF NOT EXISTS model_has_roles (
    role_id BIGINT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    model_type VARCHAR(255) NOT NULL,
    model_id BIGINT NOT NULL,
    PRIMARY KEY (role_id, model_id, model_type)
);

CREATE INDEX IF NOT EXISTS model_has_roles_model_id_model_type_idx
    ON model_has_roles (model_id, model_type);

CREATE INDEX IF NOT EXISTS users_lower_email_active_idx
    ON users (lower(email))
    WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS estados (
    id BIGINT PRIMARY KEY,
    nombre_estado VARCHAR(80) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO estados (id, nombre_estado, activo)
VALUES
    (1, 'ALMACEN', TRUE),
    (2, 'VENTANILLA', TRUE),
    (10, 'RECIBIDO', TRUE),
    (13, 'CARTERO', TRUE),
    (18, 'DEVOLUCION', TRUE),
    (25, 'CLASIFICADO', TRUE),
    (27, 'ENTREGADO', TRUE)
ON CONFLICT (id) DO UPDATE
SET nombre_estado = EXCLUDED.nombre_estado,
    activo = EXCLUDED.activo;

CREATE TABLE IF NOT EXISTS ventanilla (
    id BIGSERIAL PRIMARY KEY,
    nombre_ventanilla VARCHAR(255) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO ventanilla (nombre_ventanilla, activo)
VALUES ('Ventanilla principal', TRUE)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS paquetes_ems (
    id BIGSERIAL PRIMARY KEY,
    codigo VARCHAR(80) NOT NULL UNIQUE,
    code VARCHAR(80) NULL,
    barcode VARCHAR(80) NULL,
    nombre_destinatario VARCHAR(255) NULL,
    destinatario VARCHAR(255) NULL,
    nombre_d VARCHAR(255) NULL,
    telefono_destinatario VARCHAR(40) NULL,
    telefono VARCHAR(40) NULL,
    telefono_d VARCHAR(40) NULL,
    ciudad VARCHAR(120) NULL,
    destino VARCHAR(120) NULL,
    provincia VARCHAR(120) NULL,
    zona VARCHAR(255) NULL,
    direccion VARCHAR(255) NULL,
    peso NUMERIC(12,4) NULL,
    tipo VARCHAR(80) NULL,
    aduana VARCHAR(10) NULL,
    estado_id BIGINT NULL REFERENCES estados(id),
    fk_estado BIGINT NULL REFERENCES estados(id),
    estados_id BIGINT NULL REFERENCES estados(id),
    fk_ventanilla BIGINT NULL REFERENCES ventanilla(id),
    ventanilla VARCHAR(255) NULL,
    observaciones TEXT NULL,
    fecha_registro TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS paquetes_certi (
    id BIGSERIAL PRIMARY KEY,
    codigo VARCHAR(80) NOT NULL UNIQUE,
    code VARCHAR(80) NULL,
    barcode VARCHAR(80) NULL,
    destinatario VARCHAR(255) NULL,
    nombre_destinatario VARCHAR(255) NULL,
    nombre_d VARCHAR(255) NULL,
    telefono VARCHAR(40) NULL,
    telefono_destinatario VARCHAR(40) NULL,
    telefono_d VARCHAR(40) NULL,
    cuidad VARCHAR(120) NULL,
    ciudad VARCHAR(120) NULL,
    destino VARCHAR(120) NULL,
    provincia VARCHAR(120) NULL,
    zona VARCHAR(255) NULL,
    direccion VARCHAR(255) NULL,
    peso NUMERIC(12,4) NULL,
    tipo VARCHAR(80) NULL,
    aduana VARCHAR(10) NULL,
    fk_estado BIGINT NULL REFERENCES estados(id),
    estado_id BIGINT NULL REFERENCES estados(id),
    estados_id BIGINT NULL REFERENCES estados(id),
    fk_ventanilla BIGINT NULL REFERENCES ventanilla(id),
    ventanilla VARCHAR(255) NULL,
    observaciones TEXT NULL,
    fecha_registro TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS paquetes_contrato (
    id BIGSERIAL PRIMARY KEY,
    codigo VARCHAR(80) NOT NULL UNIQUE,
    code VARCHAR(80) NULL,
    barcode VARCHAR(80) NULL,
    nombre_d VARCHAR(255) NULL,
    destinatario VARCHAR(255) NULL,
    nombre_destinatario VARCHAR(255) NULL,
    telefono_d VARCHAR(40) NULL,
    telefono VARCHAR(40) NULL,
    telefono_destinatario VARCHAR(40) NULL,
    destino VARCHAR(120) NULL,
    provincia VARCHAR(120) NULL,
    ciudad VARCHAR(120) NULL,
    zona VARCHAR(255) NULL,
    direccion_d VARCHAR(255) NULL,
    peso NUMERIC(12,4) NULL,
    tipo VARCHAR(80) NULL,
    aduana VARCHAR(10) NULL,
    estados_id BIGINT NULL REFERENCES estados(id),
    estado_id BIGINT NULL REFERENCES estados(id),
    fk_estado BIGINT NULL REFERENCES estados(id),
    fk_ventanilla BIGINT NULL REFERENCES ventanilla(id),
    ventanilla VARCHAR(255) NULL,
    observaciones TEXT NULL,
    fecha_registro TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS paquetes_ordi (
    id BIGSERIAL PRIMARY KEY,
    codigo VARCHAR(80) NOT NULL UNIQUE,
    code VARCHAR(80) NULL,
    barcode VARCHAR(80) NULL,
    destinatario VARCHAR(255) NULL,
    nombre_destinatario VARCHAR(255) NULL,
    nombre_d VARCHAR(255) NULL,
    telefono VARCHAR(40) NULL,
    telefono_destinatario VARCHAR(40) NULL,
    telefono_d VARCHAR(40) NULL,
    ciudad VARCHAR(120) NULL,
    destino VARCHAR(120) NULL,
    provincia VARCHAR(120) NULL,
    zona VARCHAR(255) NULL,
    direccion VARCHAR(255) NULL,
    peso NUMERIC(12,4) NULL,
    tipo VARCHAR(80) NULL,
    aduana VARCHAR(10) NULL,
    fk_estado BIGINT NULL REFERENCES estados(id),
    estado_id BIGINT NULL REFERENCES estados(id),
    estados_id BIGINT NULL REFERENCES estados(id),
    fk_ventanilla BIGINT NULL REFERENCES ventanilla(id),
    ventanilla VARCHAR(255) NULL,
    observaciones TEXT NULL,
    fecha_registro TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cartero (
    id BIGSERIAL PRIMARY KEY,
    id_user BIGINT NOT NULL REFERENCES users(id),
    id_estados BIGINT NOT NULL REFERENCES estados(id),
    id_paquetes_ems BIGINT NULL REFERENCES paquetes_ems(id),
    id_paquetes_certi BIGINT NULL REFERENCES paquetes_certi(id),
    id_paquetes_contrato BIGINT NULL REFERENCES paquetes_contrato(id),
    id_paquetes_ordi BIGINT NULL REFERENCES paquetes_ordi(id),
    intento INTEGER NOT NULL DEFAULT 0,
    descripcion TEXT NULL,
    foto TEXT NULL,
    imagen TEXT NULL,
    firma TEXT NULL,
    imagen_devolucion TEXT NULL,
    recibido_por VARCHAR(120) NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT cartero_un_paquete_chk CHECK (
        num_nonnulls(id_paquetes_ems, id_paquetes_certi, id_paquetes_contrato, id_paquetes_ordi) = 1
    )
);

CREATE INDEX IF NOT EXISTS cartero_user_estado_idx
    ON cartero (id_user, id_estados);

CREATE INDEX IF NOT EXISTS cartero_paquetes_ems_idx
    ON cartero (id_paquetes_ems)
    WHERE id_paquetes_ems IS NOT NULL;

CREATE INDEX IF NOT EXISTS cartero_paquetes_certi_idx
    ON cartero (id_paquetes_certi)
    WHERE id_paquetes_certi IS NOT NULL;

CREATE INDEX IF NOT EXISTS cartero_paquetes_contrato_idx
    ON cartero (id_paquetes_contrato)
    WHERE id_paquetes_contrato IS NOT NULL;

CREATE INDEX IF NOT EXISTS cartero_paquetes_ordi_idx
    ON cartero (id_paquetes_ordi)
    WHERE id_paquetes_ordi IS NOT NULL;

CREATE TABLE IF NOT EXISTS eventos_ems (
    id BIGSERIAL PRIMARY KEY,
    codigo VARCHAR(80) NOT NULL,
    evento VARCHAR(255) NOT NULL,
    descripcion TEXT NULL,
    ciudad VARCHAR(120) NULL,
    fecha_evento TIMESTAMP NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS eventos_certi (LIKE eventos_ems INCLUDING ALL);
CREATE TABLE IF NOT EXISTS eventos_contrato (LIKE eventos_ems INCLUDING ALL);
CREATE TABLE IF NOT EXISTS eventos_ordi (LIKE eventos_ems INCLUDING ALL);

CREATE INDEX IF NOT EXISTS eventos_ems_codigo_idx ON eventos_ems (codigo);
CREATE INDEX IF NOT EXISTS eventos_certi_codigo_idx ON eventos_certi (codigo);
CREATE INDEX IF NOT EXISTS eventos_contrato_codigo_idx ON eventos_contrato (codigo);
CREATE INDEX IF NOT EXISTS eventos_ordi_codigo_idx ON eventos_ordi (codigo);
*/
print "Revisar"