# SNMP Trap Receiver with PostgreSQL Alarm Lifecycle

A production-ready **SNMPv3 trap receiver** written in Python, backed by **PostgreSQL-native alarm lifecycle management**.
This project captures SNMP traps, safely decodes vendor payloads (Huawei-friendly), and maintains **ACTIVE / HISTORICAL**
alarms directly inside PostgreSQL.

---

## Features

- SNMPv3 (authPriv) trap reception using `pysnmp`
- Safe HEX OCTET STRING decoding (Huawei alarms)
- PostgreSQL-driven alarm state machine
- ACTIVE / CLEARED alarm lifecycle
- Stateless Python receiver (DB is source of truth)
- Grafana-ready schema
- One-command bootstrap scripts

---

## Repository Structure

```
.
├── bootstrap_snmp_python310.sh   # Python 3.10 + virtualenv + SNMP deps
├── setup_postgresql.sh           # PostgreSQL schema, users, alarm logic
├── pysnmp_trap_receiver.py       # SNMP trap listener (core app)
├── postgre_sql_snmp_alarm_database.md
└── README.md
```

---

## Architecture

```
Network Device
   ↓ SNMP Trap (v3)
Python Trap Receiver
   ↓
INSERT INTO traps
   ↓
process_alarm_row()
   ↓
PostgreSQL
   ├── active_alarms
   └── historical_alarms
```

All alarm lifecycle logic is enforced inside PostgreSQL, ensuring transactional safety and eliminating duplicate active alarms.

---

## Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- sudo/root access
- SNMPv3-capable network devices

---

## Quick Start

### 1. Install Python 3.10 and Dependencies

```bash
chmod +x bootstrap_snmp_python310.sh
./bootstrap_snmp_python310.sh
```

This installs Python **3.10.14**, creates a virtual environment, and installs pinned SNMP/PostgreSQL libraries.

---

### 2. Install and Configure PostgreSQL

```bash
sudo chmod +x setup_postgresql.sh
sudo ./setup_postgresql.sh
```

Creates:
- Database: `snmptraps`
- User: `snmpuser`
- Grafana user: `grafana_user`
- Tables, indexes, and alarm lifecycle function

---

### 3. Configure Trap Receiver

Edit connection and SNMP parameters in `pysnmp_trap_receiver.py`:

```python
LISTEN_IP = "0.0.0.0"
LISTEN_PORT = 8899

DB_CONFIG = {
    "host": "localhost",
    "dbname": "snmptraps",
    "user": "snmpuser",
    "password": "toor",
}
```

---

### 4. Run the Trap Receiver

```bash
source ~/venv/bin/activate
python pysnmp_trap_receiver.py
```

Example output:

```
Listening for SNMP traps on 0.0.0.0:8899
[OK] Fault | LINK_DOWN | SITE-A
[OK] Recovery | LINK_DOWN | SITE-A
```

---

## Database Model

### Tables

| Table | Description |
|------|-------------|
| traps | Raw SNMP trap storage |
| active_alarms | Currently active alarms |
| historical_alarms | Cleared alarm history |

### Alarm Logic

Alarm transitions are handled by the PostgreSQL function:

```sql
process_alarm_row(...)
```

- `Fault` → insert/update `active_alarms`
- `Recovery` → move alarm to `historical_alarms`

---

## Grafana Integration

Use the `grafana_user` to create dashboards directly from:

- `active_alarms` (live alarms)
- `historical_alarms` (SLA, MTTR, reporting)

No middleware required.

---

## Security Notes

- SNMPv3 `authPriv` enforced
- SCRAM-SHA-256 PostgreSQL authentication
- Alarm tables are not written directly by applications

---

## License

Intended for internal, lab, or educational use.
Modify and extend freely.

---

## Status

- Production tested
- Idempotent setup scripts
- Stateless receiver
- Database-enforced alarm lifecycle
