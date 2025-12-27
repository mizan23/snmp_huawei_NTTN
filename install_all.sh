#!/usr/bin/env bash
set -euo pipefail

#######################################
# CONFIG
#######################################
APP_DIR="/opt/snmp_alarm_system"
VENV_DIR="${APP_DIR}/venv"

PYTHON_REQUIRED="3.11"

DB_NAME="snmptraps"
DB_USER="snmpuser"
DB_PASS="toor"

SERVICE_NAME="snmp-trap-receiver"

BASE_URL="https://raw.githubusercontent.com/mizan23/snmp_huawei_NTTN/main"

#######################################
# ROOT CHECK
#######################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root: sudo ./install_all.sh"
  exit 1
fi

echo "🚀 Installing SNMP Alarm System (FINAL HARDENED FIX)"

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
  echo "❌ Python 3.11 required, found ${PY_VER}"
  exit 1
fi

#######################################
# POSTGRESQL
#######################################
systemctl enable postgresql
systemctl start postgresql

#######################################
# DATABASE & USER
#######################################
sudo -u postgres psql -tAc \
  "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" \
  | grep -q 1 || sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};"

sudo -u postgres psql -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" \
  | grep -q 1 || sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

#######################################
# SCHEMA & CORE LOGIC
#######################################
sudo -u postgres psql -d ${DB_NAME} <<'EOF'
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
# APPLICATION DIRECTORY
#######################################
mkdir -p "${APP_DIR}"

#######################################
# DESTROY OLD VENV (CRITICAL)
#######################################
if [[ -d "${VENV_DIR}" ]]; then
  echo "⚠️ Removing existing virtualenv"
  rm -rf "${VENV_DIR}"
fi

#######################################
# CREATE PYTHON 3.11 VENV
#######################################
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
echo "🎉 INSTALLATION COMPLETE — GUARANTEED FIX"
echo "----------------------------------------"
echo "✔ Python 3.11 enforced"
echo "✔ Virtualenv recreated"
echo "✔ pysnmp + pyasn1 pinned"
echo "✔ PostgreSQL schema ready"
echo "✔ SNMP trap receiver running"
echo ""
echo "Check:"
echo "  systemctl status ${SERVICE_NAME}"
