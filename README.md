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
- Fully automated PostgreSQL provisioning

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

## 3️⃣ Automatic PostgreSQL Setup (RECOMMENDED)

The repository includes a **fully automated PostgreSQL setup script** that creates:

- Database
- Users
- Raw traps table
- Active alarms table
- Historical alarms table
- Core alarm lifecycle function

### ▶ Run once as root

```bash
chmod +x setup_postgres.sh
sudo ./setup_postgres.sh
```

### ✔ What this script guarantees

- Raw trap ingestion table (`traps`)
- Active alarm state table (`active_alarms`)
- Historical alarm archive (`historical_alarms`)
- Core alarm lifecycle logic (`process_alarm_row`)
- Safe to re-run (idempotent)
- Matches Python receiver and CLI exactly

---

## 4️⃣ Alarm Lifecycle (CORE LOGIC)

The database itself manages alarm state transitions.

| Incoming State | Result |
|---------------|--------|
| Fault | Insert or update active alarm |
| Repeat Fault | Update `last_seen` |
| Recovery | Move alarm to history |
| Recovery | Remove from active |

This logic is implemented in PostgreSQL via:

```sql
process_alarm_row(...)
```

---

## 5️⃣ SNMP Trap Receiver

📄 **pysnmp_trap_receiver.py**

- Receives SNMPv3 traps
- Stores all traps in `traps`
- Calls `process_alarm_row()` for lifecycle handling

Run:

```bash
sudo pysnmp_trap_receiver.py
```

---

## 6️⃣ CLI Viewer

📄 **cli_user.py**

View alarms:

```bash
cli_user.py active
cli_user.py history
```

---

## ✅ Final Result

✔ Raw traps preserved  
✔ Active alarms deduplicated  
✔ Recoveries archived automatically  
✔ PostgreSQL = alarm brain  
✔ Python = transport layer  
✔ Enterprise-grade NMS design  

---

## 📜 License

MIT
