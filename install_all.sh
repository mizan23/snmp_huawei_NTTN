#!/usr/bin/env bash
set -e

#######################################
# CONFIG
#######################################
APP_DIR="/opt/snmp_alarm_system"
VENV_DIR="/opt/pysnmp-env"

DB_NAME="snmptraps"
DB_USER="snmpuser"
DB_PASS="toor"

GRAFANA_USER="grafana_user"
GRAFANA_PASS="toor"

PYTHON_BIN="python3.10"

#######################################
# ROOT CHECK
#######################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root: sudo ./install_all.sh"
  exit 1
fi

echo "🚀 Starting FULL automatic installation..."

#######################################
# OS PACKAGES
#######################################
echo "📦 Installing OS dependencies..."
apt update
apt install -y \
  software-properties-common \
  python3.10 python3.10-venv python3-pip \
  postgresql postgresql-contrib \
  build-essential

#######################################
# POSTGRESQL SETUP
#######################################
echo "🗄 Setting up PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname='${DB_NAME}') THEN
      CREATE DATABASE ${DB_NAME};
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${DB_USER}') THEN
      CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';
   END IF;
END
\$\$;

DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${GRAFANA_USER}') THEN
      CREATE USER ${GRAFANA_USER} WITH PASSWORD '${GRAFANA_PASS}';
   END IF;
END
\$\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF

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
# PYTHON ENVIRONMENT
#######################################
echo "🐍 Creating Python virtual environment..."
${PYTHON_BIN} -m venv ${VENV_DIR}
source ${VENV_DIR}/bin/activate

pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary

#######################################
# INSTALL APPLICATION FILES
#######################################
echo "📂 Installing application files..."
mkdir -p ${APP_DIR}

cp pysnmp_trap_receiver.py ${APP_DIR}/
cp cli_user.py ${APP_DIR}/

sed -i "s|^#!/.*python|#!${VENV_DIR}/bin/python|" \
  ${APP_DIR}/pysnmp_trap_receiver.py

chmod +x ${APP_DIR}/pysnmp_trap_receiver.py
chmod +x ${APP_DIR}/cli_user.py

#######################################
# FINISH
#######################################
echo ""
echo "🎉 INSTALLATION COMPLETE"
echo "-----------------------------------"
echo "▶ Start trap receiver:"
echo "  sudo ${APP_DIR}/pysnmp_trap_receiver.py"
echo ""
echo "▶ View alarms:"
echo "  ${APP_DIR}/cli_user.py active"
echo "  ${APP_DIR}/cli_user.py history"
echo ""
echo "✅ System is fully operational"
