#!/bin/bash
set -e

echo "=== SNMP Alarm System Installer ==="

# -------------------------------
# Ask user ONCE
# -------------------------------
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

# -------------------------------
# OS dependencies
# -------------------------------
apt update
apt install -y python3-venv python3-pip postgresql

# -------------------------------
# PostgreSQL setup
# -------------------------------
sudo -u postgres psql <<EOF
CREATE DATABASE $DB_NAME;
CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
EOF

# -------------------------------
# Create tables + function (FIXED)
# -------------------------------
sudo -u postgres psql -d "$DB_NAME" <<'EOF'
CREATE TABLE IF NOT EXISTS traps (
    id BIGSERIAL PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);

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
            severity = EXCLUDED.severity,
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

# -------------------------------
# Python venv
# -------------------------------
mkdir -p "$INSTALL_DIR"
python3 -m venv "$INSTALL_DIR/venv"
source "$INSTALL_DIR/venv/bin/activate"
pip install pysnmp==4.4.12 psycopg2-binary
deactivate

# -------------------------------
# Write shared .env
# -------------------------------
cat <<EOF > "$ENV_FILE"
export DB_HOST=$DB_HOST
export DB_PORT=$DB_PORT
export DB_NAME=$DB_NAME
export DB_USER=$DB_USER
export DB_PASS=$DB_PASS
export SNMP_PORT=$SNMP_PORT
EOF

chmod 600 "$ENV_FILE"

# -------------------------------
# systemd service
# -------------------------------
cat <<EOF > /etc/systemd/system/snmp-trap-receiver.service
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

systemctl daemon-reload
systemctl enable snmp-trap-receiver.service
systemctl restart snmp-trap-receiver.service

# -------------------------------
# CLI wrapper
# -------------------------------
cat <<EOF > $INSTALL_DIR/cli
#!/bin/bash
source $ENV_FILE
exec $INSTALL_DIR/cli_user.py "\$@"
EOF

chmod +x "$INSTALL_DIR/cli"

echo "=== INSTALL COMPLETE ==="
