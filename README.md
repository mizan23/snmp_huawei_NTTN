# 📘 SNMP Alarm Management System  
Active & Historical Alarm Handling using pysnmp + PostgreSQL

Enterprise-grade SNMPv3 alarm ingestion and lifecycle management system designed for Huawei telecom environments.

---

## 🚀 Overview

This project implements a telecom-grade SNMP alarm management system with:

- SNMPv3 trap reception (Huawei compatible)
- PostgreSQL-backed alarm lifecycle engine
- Separation of Active and Historical (Recovered) alarms
- Operator-friendly CLI viewer
- Grafana-ready database schema

---

## 🧠 Architecture

Network Devices (SNMPv3)
        |
        v
pysnmp_trap_receiver.py
        |
        v
PostgreSQL
├── traps
├── active_alarms
└── historical_alarms
        |
        +── cli_user.py
        +── Grafana

---

## 🛠 Requirements

- Ubuntu 20.04 / 22.04 / 24.04
- Python 3.10
- PostgreSQL 12+
- Huawei SNMPv3 devices

---

## 1️⃣ Install Required Software

sudo apt update  
sudo apt install -y python3-pip postgresql postgresql-contrib  
pip3 install pysnmp psycopg2-binary

---

## 2️⃣ Create Virtual Environment

python3.10 -m venv /opt/pysnmp-env  
source /opt/pysnmp-env/bin/activate  

pip install --upgrade pip  
pip install pysnmp==4.4.12 psycopg2-binary

---

## 3️⃣ PostgreSQL Setup

CREATE DATABASE snmptraps;  
CREATE USER snmpuser WITH PASSWORD 'toor';  
GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;  

CREATE USER grafana_user WITH PASSWORD 'toor';

---

## 4️⃣ Tables

CREATE TABLE traps (
    id BIGSERIAL PRIMARY KEY,
    received_at TIMESTAMP NOT NULL,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);

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

---

## 5️⃣ Usage

Start trap receiver:
sudo pysnmp_trap_receiver.py

View alarms:
cli_user.py active  
cli_user.py history  

---

## ✅ Final Result

✔ Active alarms tracked  
✔ Recovery handled automatically  
✔ CLI readable output  
✔ Enterprise-grade design  

---

MIT License
