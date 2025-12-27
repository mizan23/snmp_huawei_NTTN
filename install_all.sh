#!/usr/bin/env bash
set -euo pipefail

#######################################
# ROOT CHECK
#######################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root: sudo ./install_all.sh"
  exit 1
fi

echo "🚀 Installing SNMP Alarm System (FULL FIX)"

#######################################
# INTERACTIVE DB CONFIG
#######################################
read -rp "Enter PostgreSQL database name [snmptraps]: " DB_NAME
DB_NAME=${DB_NAME:-snmptraps}

read -rp "Enter PostgreSQL user [snmpuser]: " DB_USER
DB_USER=${DB_USER:-snmpuser}

read -srp "Enter PostgreSQL password: " DB_PASS
echo ""
read -srp "Confirm PostgreSQL password: " DB_PASS_CONFIRM
echo ""

if [[ "$DB_PASS" != "$DB_PASS_CONFIRM" ]]; then
  echo "❌ Passwords do not match"
  exit 1
fi

#######################################
# CONFIG
#######################################
APP_DIR="/opt/snmp_alarm_system"
VENV_DIR="${APP_DIR}/venv"
SERVICE_NAME="snmp-trap-receiver"
BASE_URL="https://raw.githubusercontent.com/mizan23/snmp_huawei_NTTN/main"
PYTHON_REQUIRED="3.11"

#######################################
# OS DEPENDENCIES
#######################################
apt update
apt install -y \
  curl \
  postgresql postgresql-contrib \
  python3 python3-venv python3-pip \
  software-properties-common

#######################################
# PYTHON 3.11 (MANDATORY)
#######################################
if ! command -v python3.11 >/dev/null 2>&1; then
  echo "🐍 Installing Python 3.11..."
  add-apt-repository ppa:deadsnakes/ppa -y
  apt update
  apt install -y python3.11 python3.11-venv
fi

PY_VER=$(python3.11 - <<EOF
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
EOF
)

if [[ "$PY_VER" != "$PYTHON_REQUIRED" ]]; then
  echo "❌ Python 3.11 required"
  exit 1
fi

#######################################
# POSTGRESQL
#######################################
systemctl enable postgresql
systemctl start postgresql

#######################################
# DATABASE & USER (SAFE + IDEMPOTENT)
#######################################
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_database WHERE datname='${DB_NAME}'
  ) THEN
    CREATE DATABASE ${DB_NAME};
  END IF;

  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname='${DB_USER}'
  ) THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;
EOF

#######################################
# SCHEMA & CORE LOGIC
#######################################
sudo -u postgres psql -d "${DB_NAME}" <<'EOF'
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
) RETURNS VOID AS $$
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
$$ LANGUAGE plpgsql;
EOF

#######################################
# DATABASE PERMISSIONS (STORE & VIEW)
#######################################
sudo -u postgres psql -d "${DB_NAME}" <<EOF
GRANT USAGE ON SCHEMA public TO ${DB_USER};

GRANT SELECT, INSERT ON traps TO ${DB_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON active_alarms TO ${DB_USER};
GRANT SELECT, INSERT ON historical_alarms TO ${DB_USER};

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${DB_USER};

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE, SELECT ON SEQUENCES TO ${DB_USER};
EOF

#######################################
# DB CONNECTION TEST
#######################################
PGPASSWORD="${DB_PASS}" psql \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  -c "SELECT now();" >/dev/null

echo "✅ Database access verified"

#######################################
# APPLICATION DIRECTORY
#######################################
mkdir -p "${APP_DIR}"

#######################################
# CLEAN VENV
#######################################
rm -rf "${VENV_DIR}"
python3.11 -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

pip install --upgrade pip
pip install \
  pysnmp==4.4.12 \
  pyasn1==0.4.8 \
  psycopg2-binary

#######################################
# APPLICATION FILES
#######################################
curl -fsSL ${BASE_URL}/pysnmp_trap_receiver.py -o ${APP_DIR}/pysnmp_trap_receiver.py
curl -fsSL ${BASE_URL}/cli_user.py -o ${APP_DIR}/cli_user.py
chmod +x ${APP_DIR}/*.py

#######################################
# SYSTEMD SERVICE
#######################################
cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=SNMP Trap Receiver
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
ExecStart=${VENV_DIR}/bin/python ${APP_DIR}/pysnmp_trap_receiver.py
WorkingDirectory=${APP_DIR}
Restart=always
RestartSec=5
User=root
Environment=PYTHONUNBUFFERED=1
Environment=DB_NAME=${DB_NAME}
Environment=DB_USER=${DB_USER}
Environment=DB_PASS=${DB_PASS}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

#######################################
# DONE
#######################################
echo ""
echo "🎉 INSTALLATION COMPLETE — FULL FIX"
echo "----------------------------------"
echo "✔ DB variables prompted securely"
echo "✔ DB user can STORE and VIEW traps"
echo "✔ Python 3.11 enforced"
echo "✔ PostgreSQL schema ready"
echo "✔ SNMP trap receiver running"
echo ""
echo "Check status:"
echo "  systemctl status ${SERVICE_NAME}"
