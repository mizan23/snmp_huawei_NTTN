✅ STEP-BY-STEP MIGRATION (DO THIS IN ORDER)
🔹 STEP 1 — Install required software

Run exactly these commands in terminal:

sudo apt update
sudo apt install -y python3-pip postgresql postgresql-contrib
pip3 install pysnmp psycopg2-binary


✔ Installs:

pysnmp → receives traps

PostgreSQL → database

psycopg2 → Python ↔ PostgreSQL


🔹 STEP 2 — Create PostgreSQL database (copy-paste safe)
sudo -u postgres psql


Now paste one by one:

CREATE DATABASE snmptraps;
CREATE USER snmpuser WITH PASSWORD 'snmppass';
ALTER ROLE snmpuser SET client_encoding TO 'utf8';
ALTER ROLE snmpuser SET default_transaction_isolation TO 'read committed';
ALTER ROLE snmpuser SET timezone TO 'Asia/Dhaka';
GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;
\q


✔ PostgreSQL is ready



🔹 STEP 3 — Create database table
psql -h localhost -U snmpuser -d snmptraps


Password: toor

Paste:

CREATE TABLE traps (
    id SERIAL PRIMARY KEY,
    received_at TIMESTAMP,
    sender TEXT,
    raw JSONB,
    parsed JSONB
);
CREATE INDEX idx_traps_time ON traps(received_at);
CREATE INDEX idx_traps_sender ON traps(sender);
\q


✔ Database structure done




🔹 STEP 4 — Create the pysnmp trap receiver (NO coding needed)

Create a new file:

nano /usr/local/bin/pysnmp_trap_receiver.py


Paste this entire file (already adapted for your Huawei settings):




#!/opt/pysnmp-venv/bin/python
# ==========================================================
# pysnmp SNMPv3 Trap Receiver (FINAL FIXED VERSION)
# - Python 3.10 (venv)
# - pysnmp 4.4.12
# - Huawei iMaster NCE compatible
# - AuthPriv (SHA-256 + AES-128)
# - EngineID explicitly bound
# - Stores traps in PostgreSQL
# ==========================================================

import json
from datetime import datetime
from zoneinfo import ZoneInfo

import psycopg2

from pysnmp.entity import engine, config
from pysnmp.carrier.asyncore.dgram import udp
from pysnmp.entity.rfc3413 import ntfrcv


# -------------------------
# BASIC SETTINGS
# -------------------------

TZ = ZoneInfo("Asia/Dhaka")

LISTEN_IP = "0.0.0.0"
LISTEN_PORT = 8899

# PostgreSQL connection
DB_CONFIG = {
    "host": "localhost",
    "dbname": "snmptraps",
    "user": "snmpuser",
    "password": "toor",   # <-- UPDATED PASSWORD
}

# SNMPv3 credentials (MUST MATCH HUAWEI)
SNMP_USER = "snmpuser"
AUTH_KEY = "Fiber@Dwdm@9800"
PRIV_KEY = "Fiber@Dwdm@9800"

# Huawei SNMP Engine ID
# From snmptrapd.conf:
#   0x8000137001C0A82A05
HUAWEI_ENGINE_ID = b"\x80\x00\x13\x70\x01\xc0\xa8\x2a\x05"


# -------------------------
# SNMP ENGINE SETUP
# -------------------------

snmpEngine = engine.SnmpEngine()

# Bind SNMPv3 user to Huawei engineID (CRITICAL)
config.addV3User(
    snmpEngine,
    SNMP_USER,
    config.usmHMAC192SHA256AuthProtocol,   # SHA-256
    AUTH_KEY,
    config.usmAesCfb128Protocol,           # AES-128
    PRIV_KEY,
    securityEngineId=HUAWEI_ENGINE_ID
)

# Security level: authPriv
config.addTargetParams(
    snmpEngine,
    "trap-creds",
    SNMP_USER,
    "authPriv"
)

config.addContext(snmpEngine, "")

# Let SNMP engine own the transport (CORRECT way)
config.addTransport(
    snmpEngine,
    udp.domainName,
    udp.UdpTransport().openServerMode((LISTEN_IP, LISTEN_PORT))
)


# -------------------------
# TRAP CALLBACK
# -------------------------

def cbFun(snmpEngine, stateRef, contextEngineId, contextName, varBinds, cbCtx):
    # Sender IP
    transportDomain, transportAddress = snmpEngine.msgAndPduDsp.getTransportInfo(stateRef)
    sender_ip = transportAddress[0]

    received_at = datetime.now(TZ)

    vars_list = []
    for oid, val in varBinds:
        vars_list.append({
            "oid": str(oid),
            "value": val.prettyPrint()
        })

    # Store in PostgreSQL
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    cur.execute(
        """
        INSERT INTO traps (received_at, sender, raw, parsed)
        VALUES (%s, %s, %s, %s)
        """,
        (
            received_at,
            sender_ip,
            json.dumps(vars_list),
            json.dumps(vars_list),
        )
    )
    conn.commit()
    cur.close()
    conn.close()

    print(f"[+] Trap received from {sender_ip}")


# Register trap receiver
ntfrcv.NotificationReceiver(snmpEngine, cbFun)

print(f"Listening for SNMP traps on {LISTEN_IP}:{LISTEN_PORT}")


# -------------------------
# START DISPATCHER
# -------------------------

try:
    snmpEngine.transportDispatcher.jobStarted(1)
    snmpEngine.transportDispatcher.runDispatcher()
except KeyboardInterrupt:
    print("\nStopping trap receiver...")
    snmpEngine.transportDispatcher.closeDispatcher()



✅ RUN IT
sudo chmod +x /usr/local/bin/pysnmp_trap_receiver.py
sudo /usr/local/bin/pysnmp_trap_receiver.py


Expected:

Listening for SNMP traps on 0.0.0.0:8899


Trigger a Huawei alarm → you should see:

[+] Trap received from 192.168.42.5

























🔹 STEP 2 — Create a virtual environment (IMPORTANT)

This keeps everything clean.

python3.10 -m venv /opt/pysnmp-env


Activate it:

source /opt/pysnmp-env/bin/activate


You will see:

(pysnmp-env)


🔹 STEP 3 — Install compatible libraries INSIDE the venv
pip install --upgrade pip
pip install pysnmp==4.4.12 psycopg2-binary


✔ pysnmp 4.4.12 = stable & proven
✔ Works perfectly with SNMPv3 + Huawei



✅ VERIFY DATABASE
psql -h localhost -U snmpuser -d snmptraps
SELECT id, sender, received_at FROM traps ORDER BY id DESC LIMIT 5;


Rows should appear ✅




