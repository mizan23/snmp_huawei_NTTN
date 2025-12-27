# Huawei SNMPv3 Alarm Management System  
*(pysnmp + PostgreSQL)*

This project provides a **production-ready SNMPv3 alarm management system**
compatible with **Huawei iMaster NCE**.

It includes:

- SNMPv3 trap receiver
- Active → historical alarm lifecycle
- PostgreSQL backend
- Human-readable CLI (`active` / `history`)
- Tested with Huawei **SHA-256 + AES-128 (AuthPriv)**

---

## 📁 Repository Structure

```text
.
├── pysnmp_trap_receiver.py   # Receives SNMP traps & updates alarms
├── alarm_processor.py        # Moves recovered alarms to history
├── cli_user.py               # CLI: view active & historical alarms
└── README.md
```

---
---

## ✅ STEP-BY-STEP DEPLOYMENT  
*(Follow in order)*

---

## 🔹 STEP 1 — Install System Requirements

```bash
sudo apt update
sudo apt install -y \
  python3.10 \
  python3.10-venv \
  python3-pip \
  postgresql \
  postgresql-contrib
```

---

## 🔹 STEP 2 — Create PostgreSQL Database

```bash
sudo -u postgres psql
```

```sql
CREATE DATABASE snmptraps;
CREATE USER snmpuser WITH PASSWORD 'toor';
ALTER ROLE snmpuser SET client_encoding TO 'utf8';
ALTER ROLE snmpuser SET default_transaction_isolation TO 'read committed';
ALTER ROLE snmpuser SET timezone TO 'Asia/Dhaka';
GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;
```

```sql
\q
```

### ✔ Database Summary

| Item | Value |
|----|----|
| Database | snmptraps |
| User | snmpuser |
| Password | toor |
| Timezone | Asia/Dhaka |

---

## 🔹 STEP 3 — Create Database Tables

```bash
psql -h localhost -U snmpuser -d snmptraps
```

```sql
CREATE TABLE active_alarms (
    alarm_id TEXT PRIMARY KEY,
    first_seen TIMESTAMP,
    last_seen TIMESTAMP,
    site TEXT,
    device_type TEXT,
    source TEXT,
    severity TEXT,
    alarm_code TEXT,
    description TEXT,
    raw JSONB
);

CREATE TABLE historical_alarms (
    alarm_id TEXT,
    first_seen TIMESTAMP,
    last_seen TIMESTAMP,
    recovery_time TIMESTAMP,
    site TEXT,
    device_type TEXT,
    source TEXT,
    severity TEXT,
    alarm_code TEXT,
    description TEXT,
    raw JSONB
);

CREATE INDEX idx_active_last_seen ON active_alarms(last_seen);
CREATE INDEX idx_hist_recovery ON historical_alarms(recovery_time);
```

```sql
\q
```

---

## 🔹 STEP 4 — Python Virtual Environment

```bash
python3.10 -m venv /opt/pysnmp-env
source /opt/pysnmp-env/bin/activate
```

---

## 🔹 STEP 5 — Install Python Libraries

```bash
pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary
```

---

## 🔹 STEP 6 — Configure SNMP Trap Receiver

```python
SNMP_USER = "snmpuser"
AUTH_KEY  = "Fiber@Dwdm@9800"
PRIV_KEY  = "Fiber@Dwdm@9800"
HUAWEI_ENGINE_ID = b"\x80\x00\x13\x70\x01\xc0\xa8\x2a\x05"
```

---

## 🔹 STEP 7 — Start Trap Receiver

```bash
chmod +x pysnmp_trap_receiver.py
sudo ./pysnmp_trap_receiver.py
```

---

## 🔹 STEP 9 — CLI Usage

```bash
chmod +x cli_user.py
./cli_user.py active
./cli_user.py history
```

---

## ✅ Final Result

✔ Huawei SNMPv3 compatible  
✔ AuthPriv (SHA-256 + AES-128)  
✔ Active / historical lifecycle  
✔ PostgreSQL backend  
✔ CLI monitoring  
✔ GitHub-ready  
✔ Enterprise-grade design  
