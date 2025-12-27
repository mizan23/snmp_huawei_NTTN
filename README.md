# 📘 SNMP Alarm Management System
**Active & Historical Alarm Handling using pysnmp + PostgreSQL**

Enterprise-grade SNMPv3 alarm ingestion and lifecycle management system designed for Huawei NCE / telecom environments.

---

## 🚀 Overview

This project implements a **telecom-grade SNMP alarm management system** with:

- SNMPv3 trap reception (Huawei compatible)
- PostgreSQL-backed alarm lifecycle engine (**raw → active → history**)
- Separation of **Active** and **Historical (Recovered)** alarms
- Operator-friendly CLI viewer
- Grafana-ready database schema

You can deploy this system in **two ways**:
1. **Automatic (recommended)** – one command, fully automated  
2. **Manual** – step-by-step, full control  

---

## 🧠 Architecture

```text
Network Devices (SNMPv3)
        |
        v
pysnmp_trap_receiver.py
        |
        v
PostgreSQL (Alarm Engine)
├── traps              (raw traps / audit)
├── active_alarms      (currently active alarms)
├── historical_alarms  (cleared alarms)
└── process_alarm_row  (core lifecycle logic)
        |
        +── cli_user.py
        +── Grafana
```

---

## 🛠 Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- Root access (`sudo`)
- Internet connectivity
- Huawei devices sending **SNMPv3 AuthPriv traps**

---

# ⚡ OPTION A — Automatic Installation (RECOMMENDED)

This method installs **everything automatically**:

✔ OS dependencies  
✔ Python 3.10 + virtual environment  
✔ pysnmp + psycopg2  
✔ PostgreSQL installation & configuration  
✔ Raw / Active / History tables  
✔ Alarm lifecycle function  
✔ Trap receiver deployment  
✔ CLI viewer deployment  

### ▶ One command install

```bash
chmod +x install_all.sh
sudo ./install_all.sh
```

After completion, the system is **fully operational**.

---

# 🛠 OPTION B — Manual Installation (STEP-BY-STEP)

Use this if you want **full visibility and control**.

---

## 1️⃣ Install Required Software

```bash
sudo apt update
sudo apt install -y python3-pip postgresql postgresql-contrib python3.10 python3.10-venv
```

---

## 2️⃣ Create Python Virtual Environment

```bash
python3.10 -m venv /opt/pysnmp-env
source /opt/pysnmp-env/bin/activate
```

```text
(pysnmp-env)
```

Install libraries:

```bash
pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary
```

---

## 3️⃣ PostgreSQL Setup (MANUAL)

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE snmptraps;

CREATE USER snmpuser WITH PASSWORD 'toor';
CREATE USER grafana_user WITH PASSWORD 'toor';

GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;
\q
```

### Create tables & core logic

```bash
sudo -u postgres psql -d snmptraps
```

```sql
-- Raw traps
CREATE TABLE traps (
    id BIGSERIAL PRIMARY KEY,
    received_at TIMESTAMP NOT NULL,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);

-- Active alarms
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

-- Historical alarms
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

-- Core lifecycle function
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

## 4️⃣ Deploy Python Applications (MANUAL)

```bash
mkdir -p /opt/snmp_alarm_system
cp pysnmp_trap_receiver.py /opt/snmp_alarm_system/
cp cli_user.py /opt/snmp_alarm_system/

chmod +x /opt/snmp_alarm_system/*.py
```

---

## ▶ Running the System

### Start SNMP Trap Receiver

```bash
sudo /opt/snmp_alarm_system/pysnmp_trap_receiver.py
```

### CLI Usage

```bash
/opt/snmp_alarm_system/cli_user.py active
/opt/snmp_alarm_system/cli_user.py history
```

---

## 🧠 Alarm Lifecycle Summary

| State | Result |
|-----|-------|
| Fault | Insert/update active alarm |
| Repeat Fault | Update last_seen |
| Recovery | Move to history |
| Recovery | Remove from active |

PostgreSQL acts as the **alarm brain**.

---

## ✅ Final Result

✔ Raw traps preserved  
✔ Active alarms deduplicated  
✔ Recoveries archived automatically  
✔ Manual or automatic install supported  
✔ Enterprise-grade NMS design  

---

## 📜 License

MIT
