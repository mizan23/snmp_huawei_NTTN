# 📘 SNMP Alarm Management System
**Active & Historical Alarm Handling using pysnmp + PostgreSQL**

Enterprise-grade SNMPv3 alarm ingestion and lifecycle management system designed for Huawei NCE / telecom environments.

---

## 🚀 Overview

This project implements a **telecom-grade SNMP alarm management system** with:

- SNMPv3 trap reception (Huawei compatible)
- PostgreSQL-backed alarm lifecycle engine
- Separation of **Active** and **Historical (Recovered)** alarms
- Operator-friendly CLI viewer
- Grafana-ready database schema

The architecture mirrors how real **NMS / EMS systems** operate internally.

---

## 🧠 Architecture

```text
Network Devices (SNMPv3)
        |
        v
pysnmp_trap_receiver.py
        |
        v
PostgreSQL
├── traps              (raw traps / audit)
├── active_alarms      (currently active alarms)
└── historical_alarms  (cleared alarms)
        |
        +── cli_user.py
        +── Grafana
```

---

## 🛠 Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- Python **3.10**
- PostgreSQL **12+**
- Huawei devices sending **SNMPv3 AuthPriv traps**

---

## 1️⃣ Install Required Software

```bash
sudo apt update
sudo apt install -y python3-pip postgresql postgresql-contrib
pip3 install pysnmp psycopg2-binary
```

**Installs:**

- `pysnmp` → SNMP trap reception
- `PostgreSQL` → Alarm database
- `psycopg2` → Python ↔ PostgreSQL connector

---

## 2️⃣ Create Python Virtual Environment (IMPORTANT)

```bash
python3.10 -m venv /opt/pysnmp-env
source /opt/pysnmp-env/bin/activate
```

You should see:

```text
(pysnmp-env)
```

Install compatible libraries **inside the venv**:

```bash
pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary
```

✔ **pysnmp 4.4.12** is stable and proven with Huawei SNMPv3

---

## 3️⃣ PostgreSQL Setup (FROM SCRATCH)

### 3.1 Create Database & Users

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE snmptraps;

CREATE USER snmpuser WITH PASSWORD 'toor';
GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;

CREATE USER grafana_user WITH PASSWORD 'toor';
\q
```

---

### 3.2 Raw Traps Table

```sql
CREATE TABLE traps (
    id BIGSERIAL PRIMARY KEY,
    received_at TIMESTAMP NOT NULL,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);
```

---

### 3.3 Active Alarms Table

```sql
CREATE TABLE active_alarms (
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

CREATE UNIQUE INDEX uq_active_alarm
ON active_alarms (site, device_type, source, alarm_code);
```

---

### 3.4 Historical Alarms Table

```sql
CREATE TABLE historical_alarms (
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
```

---

## 4️⃣ Alarm Lifecycle Function (CORE LOGIC)

```sql
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
```

---

## 5️⃣ SNMP Trap Receiver

📄 **/usr/local/bin/pysnmp_trap_receiver.py**  
(See full validated production code in this repository)

---

## 6️⃣ CLI Viewer

📄 **/usr/local/bin/cli_user.py**  
Displays active and historical alarms in a human-readable format.

---

## 7️⃣ Usage

```bash
chmod +x pysnmp_trap_receiver.py cli_user.py
sudo pysnmp_trap_receiver.py
```

View alarms:

```bash
cli_user.py active
cli_user.py history
```

---

## ✅ Final Result

✔ Active alarms tracked  
✔ Recovery automatically moves alarms to history  
✔ CLI human-readable output  
✔ Huawei hex alarms decoded  
✔ Grafana-ready schema  
✔ GitHub-ready documentation  
✔ Enterprise-grade design  

---

## 📜 License

MIT
