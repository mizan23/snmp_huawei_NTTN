#!/usr/bin/env bash
set -e

# ================================
# CONFIGURATION
# ================================
DB_NAME="snmptraps"
DB_USER="snmpuser"
DB_PASS="toor"

GRAFANA_USER="grafana_user"
GRAFANA_PASS="toor"

# ================================
# CHECK ROOT
# ================================
if [[ $EUID -ne 0 ]]; then
  echo "❌ Please run as root: sudo ./setup_postgresql.sh"
  exit 1
fi

echo "✅ Running PostgreSQL automatic setup..."

# ================================
# INSTALL POSTGRESQL IF NEEDED
# ================================
if ! command -v psql >/dev/null 2>&1; then
  echo "📦 Installing PostgreSQL..."
  apt update
  apt install -y postgresql postgresql-contrib
else
  echo "✔ PostgreSQL already installed"
fi

# ================================
# START POSTGRES SERVICE
# ================================
systemctl enable postgresql
systemctl start postgresql

# ================================
# CREATE DATABASE & USERS
# ================================
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
      CREATE DATABASE ${DB_NAME};
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
      CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${GRAFANA_USER}') THEN
      CREATE USER ${GRAFANA_USER} WITH PASSWORD '${GRAFANA_PASS}';
   END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

# ================================
# CREATE SCHEMA, TABLES, FUNCTION
# ================================
sudo -u postgres psql -d ${DB_NAME} <<EOF

-- -------------------------------
-- TABLES
-- -------------------------------
CREATE TABLE IF NOT EXISTS traps (
    id BIGSERIAL PRIMARY KEY,
    received_at TIMESTAMP NOT NULL,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);

CREATE TABLE IF NOT EXISTS active_alarms (
    alarm_id BIGSERIAL PRIMARY KEY,
    first_seen TIMESTAMP NOT NULL,
    last_seen TIMESTAMP NOT NULL,
    site TEXT,
    device_type TEXT,
    source TEXT,
    alarm_code TEXT,
    severity TEXT,
    description TEXT,
    device_time TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_alarm
ON active_alarms (site, device_type, source, alarm_code);

CREATE TABLE IF NOT EXISTS historical_alarms (
    alarm_id BIGINT,
    first_seen TIMESTAMP NOT NULL,
    last_seen TIMESTAMP NOT NULL,
    recovery_time TIMESTAMP NOT NULL,
    site TEXT,
    device_type TEXT,
    source TEXT,
    alarm_code TEXT,
    severity TEXT,
    description TEXT,
    device_time TEXT
);

-- -------------------------------
-- ALARM LIFECYCLE FUNCTION
-- -------------------------------
CREATE OR REPLACE FUNCTION process_alarm_row(
    p_received_at TIMESTAMP,
    p_site TEXT,
    p_device_type TEXT,
    p_source TEXT,
    p_alarm_code TEXT,
    p_severity TEXT,
    p_description TEXT,
    p_state TEXT,
    p_device_time TEXT
) RETURNS VOID AS \$\$
BEGIN
    IF p_state = 'Fault' THEN
        INSERT INTO active_alarms (
            first_seen, last_seen,
            site, device_type, source,
            alarm_code, severity,
            description, device_time
        )
        VALUES (
            p_received_at, p_received_at,
            p_site, p_device_type, p_source,
            p_alarm_code, p_severity,
            p_description, p_device_time
        )
        ON CONFLICT (site, device_type, source, alarm_code)
        DO UPDATE SET
            last_seen = EXCLUDED.last_seen,
            severity  = EXCLUDED.severity,
            description = EXCLUDED.description;
    END IF;

    IF p_state = 'Recovery' THEN
        INSERT INTO historical_alarms
        SELECT alarm_id, first_seen, last_seen, p_received_at,
               site, device_type, source,
               alarm_code, severity, description, device_time
        FROM active_alarms
        WHERE site = p_site
          AND device_type = p_device_type
          AND source = p_source
          AND alarm_code = p_alarm_code;

        DELETE FROM active_alarms
        WHERE site = p_site
          AND device_type = p_device_type
          AND source = p_source
          AND alarm_code = p_alarm_code;
    END IF;
END;
\$\$ LANGUAGE plpgsql;

-- ================================
-- PERMISSIONS (CRITICAL FIX)
-- ================================

-- Allow schema usage
GRANT USAGE ON SCHEMA public TO ${DB_USER};

-- Table privileges
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO ${DB_USER};

-- Function execution
GRANT EXECUTE
ON ALL FUNCTIONS IN SCHEMA public
TO ${DB_USER};

-- Default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO ${DB_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT EXECUTE
ON FUNCTIONS TO ${DB_USER};

EOF

echo "🎉 PostgreSQL setup COMPLETE"
echo "➡ Database      : ${DB_NAME}"
echo "➡ App user      : ${DB_USER}"
echo "➡ Grafana user  : ${GRAFANA_USER}"
echo "➡ Permissions   : FULL (tables + functions)"
