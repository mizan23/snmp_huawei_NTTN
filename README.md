# Huawei SNMPv3 Alarm Management System (pysnmp + PostgreSQL)

This project provides a **production-ready SNMPv3 alarm management system**
compatible with **Huawei iMaster NCE**.

It includes:
- SNMPv3 trap receiver
- Active → historical alarm lifecycle
- PostgreSQL backend
- Human-readable CLI (`active` / `history`)
- Tested with Huawei SHA-256 + AES-128 (AuthPriv)

---

## 📁 Repository Structure

```text
.
├── pysnmp_trap_receiver.py   # Receives SNMP traps & updates alarms
├── alarm_processor.py        # Moves recovered alarms to history
├── cli_user.py               # CLI: view active & historical alarms
└── README.md
✅ STEP-BY-STEP DEPLOYMENT (FOLLOW IN ORDER)
🔹 STEP 1 — Install System Requirements
bash
Copy code
sudo apt update
sudo apt install -y \
  python3.10 \
  python3.10-venv \
  python3-pip \
  postgresql \
  postgresql-contrib
🔹 STEP 2 — Create PostgreSQL Database
bash
Copy code
sudo -u postgres psql
Run one by one:

sql
Copy code
CREATE DATABASE snmptraps;

CREATE USER snmpuser WITH PASSWORD 'toor';

ALTER ROLE snmpuser SET client_encoding TO 'utf8';
ALTER ROLE snmpuser SET default_transaction_isolation TO 'read committed';
ALTER ROLE snmpuser SET timezone TO 'Asia/Dhaka';

GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;
Exit:

sql
Copy code
\q
✔ Database Summary
Item	Value
Database	snmptraps
User	snmpuser
Password	toor
Timezone	Asia/Dhaka

🔹 STEP 3 — Create Database Tables
bash
Copy code
psql -h localhost -U snmpuser -d snmptraps
sql
Copy code
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
Exit:

sql
Copy code
\q
✔ Database structure ready

🔹 STEP 4 — Create Python Virtual Environment (IMPORTANT)
bash
Copy code
python3.10 -m venv /opt/pysnmp-env
source /opt/pysnmp-env/bin/activate
You should see:

text
Copy code
(pysnmp-env)
🔹 STEP 5 — Install Compatible Python Libraries
bash
Copy code
pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary
✔ pysnmp 4.4.12 — Huawei-tested
✔ Stable SNMPv3 AuthPriv support

🔹 STEP 6 — Configure SNMP Trap Receiver
Edit pysnmp_trap_receiver.py and verify:

python
Copy code
SNMP_USER = "snmpuser"
AUTH_KEY  = "Fiber@Dwdm@9800"
PRIV_KEY  = "Fiber@Dwdm@9800"

HUAWEI_ENGINE_ID = b"\x80\x00\x13\x70\x01\xc0\xa8\x2a\x05"
These must exactly match Huawei iMaster NCE.

🔹 STEP 7 — Start SNMP Trap Receiver
bash
Copy code
chmod +x pysnmp_trap_receiver.py
sudo ./pysnmp_trap_receiver.py
Expected:

text
Copy code
Listening for SNMP traps on 0.0.0.0:8899
When an alarm is triggered:

text
Copy code
[+] Trap received from 192.168.42.5
🔹 STEP 8 — Alarm Lifecycle
New traps → stored in active_alarms

Recovery traps → moved to historical_alarms

last_seen updates automatically

Raw Huawei payload stored as JSONB

✔ Active alarms tracked
✔ Recoveries archived
✔ No duplicates

🔹 STEP 9 — CLI Usage
Make CLI executable:

bash
Copy code
chmod +x cli_user.py
View active alarms
bash
Copy code
./cli_user.py active
View historical alarms
bash
Copy code
./cli_user.py history
Output is human-readable, severity-aware, and Huawei-decoded.

🔹 STEP 10 — Verify Database
bash
Copy code
psql -h localhost -U snmpuser -d snmptraps
sql
Copy code
SELECT alarm_id, source, last_seen
FROM active_alarms
ORDER BY last_seen DESC
LIMIT 5;
Rows should appear ✅

✅ Final Result
✔ Huawei SNMPv3 compatible
✔ AuthPriv (SHA-256 + AES-128)
✔ Active / historical lifecycle
✔ PostgreSQL backend
✔ CLI monitoring
✔ GitHub-ready
✔ Enterprise-grade design

