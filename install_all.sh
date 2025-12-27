#!/usr/bin/env bash
set -euo pipefail

#######################################
# ROOT CHECK
#######################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root: sudo ./install_all.sh"
  exit 1
fi

echo "🚀 Installing SNMP Alarm System (FINAL FIX + PORT PROMPT)"

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
# SNMP CONFIG
#######################################
read -rp "Enter SNMP listening port [162]: " SNMP_PORT
SNMP_PORT=${SNMP_PORT:-162}

if ! [[ "$SNMP_PORT" =~ ^[0-9]+$ ]] || (( SNMP_PORT < 1 || SNMP_PORT > 65535 )); then
  echo "❌ Invalid SNMP port"
  exit 1
fi

#######################################
# CONFIG
#######################################
APP_DIR="/opt/snmp_alarm_system"
VENV_DIR="${APP_DIR}/venv"
SERVICE_NAME="snmp-trap-receiver"
BASE_URL="https://raw.githubusercontent.com/mizan23/snmp_huawei_NTTN/main"

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
# PYTHON 3.11
#######################################
if ! command -v python3.11 >/dev/null 2>&1; then
  add-apt-repository ppa:deadsnakes/ppa -y
  apt update
  apt install -y python3.11 python3.11-venv
fi

#######################################
# POSTGRESQL SERVICE
#######################################
systemctl enable postgresql
systemctl start postgresql

#######################################
# CREATE DATABASE
#######################################
if ! sudo -u postgres psql -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  echo "🗄️ Creating database ${DB_NAME}"
  sudo -u postgres psql -d postgres -c "CREATE DATABASE ${DB_NAME};"
fi

#######################################
# CREATE USER
#######################################
if ! sudo -u postgres psql -d postgres -tAc \
  "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1; then
  sudo -u postgres psql -d postgres -c \
    "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';"
fi

sudo -u postgres psql -d postgres -c \
  "ALTER DATABASE ${DB_NAME} OWNER TO ${DB_USER};"

#######################################
# SCHEMA
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
EOF

#######################################
# PERMISSIONS
#######################################
sudo -u postgres psql -d "${DB_NAME}" <<EOF
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT SELECT, INSERT ON traps TO ${DB_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON active_alarms TO ${DB_USER};
GRANT SELECT, INSERT ON historical_alarms TO ${DB_USER};
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
EOF

#######################################
# DB TEST (TCP)
#######################################
PGPASSWORD="${DB_PASS}" psql \
  -h 127.0.0.1 \
  -U "${DB_USER}" \
  -d "${DB_NAME}" \
  -c "SELECT 1;" >/dev/null

echo "✅ Database verified"

#######################################
# APP SETUP
#######################################
mkdir -p "${APP_DIR}"
rm -rf "${VENV_DIR}"
python3.11 -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

pip install --upgrade pip
pip install pysnmp==4.4.12 pyasn1==0.4.8 psycopg2-binary

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
Environment=DB_HOST=127.0.0.1
Environment=DB_PORT=5432
Environment=SNMP_PORT=${SNMP_PORT}

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
echo "🎉 INSTALLATION COMPLETE"
echo "------------------------"
echo "✔ SNMP port set to ${SNMP_PORT}"
echo "✔ Database ready"
echo "✔ Trap receiver running"
echo ""
echo "Check:"
echo "  systemctl status ${SERVICE_NAME}"
