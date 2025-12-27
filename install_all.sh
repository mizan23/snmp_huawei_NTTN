#!/bin/bash
set -e

echo "======================================================"
echo " SNMP Huawei NTTN Alarm System - FINAL FIX INSTALLER"
echo " Python 3.10 enforced (pysnmp compatible)"
echo "======================================================"

# ------------------------------------------------------
# Root check
# ------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root: sudo ./install_all.sh"
  exit 1
fi

# ------------------------------------------------------
# User input
# ------------------------------------------------------
read -p "DB Host [127.0.0.1]: " DB_HOST
read -p "DB Port [5432]: " DB_PORT
read -p "DB Name [snmptraps]: " DB_NAME
read -p "DB User [snmpuser]: " DB_USER
read -s -p "DB Password: " DB_PASS
echo
read -p "SNMP Listen Port [8899]: " SNMP_PORT

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-snmptraps}"
DB_USER="${DB_USER:-snmpuser}"
SNMP_PORT="${SNMP_PORT:-8899}"

INSTALL_DIR="/opt/snmp_alarm_system"
ENV_FILE="$INSTALL_DIR/.env"
SERVICE_FILE="/etc/systemd/system/snmp-trap-receiver.service"

# ------------------------------------------------------
# Base OS packages
# ------------------------------------------------------
echo "[+] Installing OS dependencies..."
apt update -y
apt install -y \
  software-properties-common \
  build-essential \
  postgresql \
  postgresql-contrib

# ------------------------------------------------------
# Install Python 3.10 (CRITICAL FIX)
# ------------------------------------------------------
echo "[+] Installing Python 3.10 (pysnmp compatible)..."

add-apt-repository -y ppa:deadsnakes/ppa
apt update -y
apt install -y python3.10 python3.10-venv python3.10-distutils

PYTHON_BIN="/usr/bin/python3.10"

# ------------------------------------------------------
# PostgreSQL startup
# ------------------------------------------------------
systemctl enable postgresql
systemctl start postgresql

# ------------------------------------------------------
# PostgreSQL DB & user (SAFE / IDEMPOTENT)
# ------------------------------------------------------
echo "[+] Configuring PostgreSQL..."

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE DATABASE $DB_NAME"

sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS'"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER"

# ------------------------------------------------------
# Database schema + alarm function
# ------------------------------------------------------
echo "[+] Creating database schema..."

sudo -u postgres psql -d "$DB_NAME" <<'EOF'
CREATE TABLE IF NOT EXISTS active_alarms (
    alarm_id BIGSERIAL PRIMARY KEY,
    first_seen TIMESTAMPTZ NOT NULL,
    last_seen TIMESTAMPTZ NOT NULL,
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
    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    recovery_time TIMESTAMPTZ,
    site TEXT,
    device_type TEXT,
    source TEXT,
    alarm_code TEXT,
    severity TEXT,
    description TEXT,
    device_time TEXT
);

DROP FUNCTION IF EXISTS process_alarm_row;

CREATE FUNCTION process_alarm_row(
    p_received_at TIMESTAMPTZ,
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

# ------------------------------------------------------
# Install application files
# ------------------------------------------------------
echo "[+] Installing application files..."

mkdir -p "$INSTALL_DIR"
cp pysnmp_trap_receiver.py "$INSTALL_DIR/"
cp cli_user.py "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/"*.py

# ------------------------------------------------------
# Python virtual environment (PYTHON 3.10)
# ------------------------------------------------------
echo "[+] Creating Python 3.10 virtual environment..."

$PYTHON_BIN -m venv "$INSTALL_DIR/venv"

"$INSTALL_DIR/venv/bin/pip" install --upgrade pip setuptools wheel

# 🔒 HARD PIN (STABLE + TESTED)
"$INSTALL_DIR/venv/bin/pip" install \
  pysnmp==4.4.12 \
  pyasn1==0.4.8 \
  pyasn1-modules==0.2.8 \
  psycopg2-binary

# ------------------------------------------------------
# Environment file (systemd-safe)
# ------------------------------------------------------
echo "[+] Writing environment file..."

cat <<EOF > "$ENV_FILE"
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
SNMP_PORT=$SNMP_PORT
EOF

chmod 600 "$ENV_FILE"

# ------------------------------------------------------
# systemd service
# ------------------------------------------------------
echo "[+] Creating systemd service..."

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=SNMP Trap Receiver
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/pysnmp_trap_receiver.py
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------
# Enable & start service
# ------------------------------------------------------
echo "[+] Enabling and starting service..."

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable snmp-trap-receiver.service
systemctl restart snmp-trap-receiver.service

echo "======================================================"
echo " INSTALL COMPLETE"
echo "======================================================"
echo " Verify:"
echo "   sudo systemctl status snmp-trap-receiver.service"
