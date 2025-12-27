#!/usr/bin/env python3
import os
import json
from datetime import datetime
from zoneinfo import ZoneInfo

import psycopg2
from pysnmp.entity import engine, config
from pysnmp.carrier.asyncore.dgram import udp
from pysnmp.entity.rfc3413 import ntfrcv

# =========================================================
# STRICT ENVIRONMENT VALIDATION (NO DEFAULTS)
# =========================================================

REQUIRED_ENV = [
    "SNMP_PORT",
    "DB_HOST",
    "DB_PORT",
    "DB_NAME",
    "DB_USER",
    "DB_PASS",
]

missing = [v for v in REQUIRED_ENV if v not in os.environ]
if missing:
    raise RuntimeError(
        f"Missing required environment variables: {', '.join(missing)}"
    )

# =========================================================
# CONFIG — ONLY FROM install_all.sh / systemd
# =========================================================

TZ = ZoneInfo("Asia/Dhaka")

LISTEN_IP = "0.0.0.0"
LISTEN_PORT = int(os.environ["SNMP_PORT"])

DB_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ["DB_PORT"]),
    "dbname": os.environ["DB_NAME"],
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASS"],
}

# =========================================================
# SNMPv3 SETTINGS (Huawei)
# =========================================================

SNMP_USER = "snmpuser"
AUTH_KEY = "Fiber@Dwdm@9800"
PRIV_KEY = "Fiber@Dwdm@9800"

# Huawei Engine ID (must match device)
HUAWEI_ENGINE_ID = b"\x80\x00\x13\x70\x01\xc0\xa8\x2a\x05"

# =========================================================
# SNMP ENGINE SETUP
# =========================================================

snmpEngine = engine.SnmpEngine()

config.addV3User(
    snmpEngine,
    SNMP_USER,
    config.usmHMAC192SHA256AuthProtocol,
    AUTH_KEY,
    config.usmAesCfb128Protocol,
    PRIV_KEY,
    securityEngineId=HUAWEI_ENGINE_ID
)

config.addTargetParams(
    snmpEngine,
    "trap-creds",
    SNMP_USER,
    "authPriv"
)

config.addContext(snmpEngine, "")

# 🔥 LISTEN ON INSTALLER-PROVIDED PORT
config.addTransport(
    snmpEngine,
    udp.domainName,
    udp.UdpTransport().openServerMode((LISTEN_IP, LISTEN_PORT))
)

# =========================================================
# TRAP CALLBACK
# =========================================================

def cbFun(snmpEngine, stateRef, contextEngineId, contextName, varBinds, cbCtx):
    transportDomain, transportAddress = snmpEngine.msgAndPduDsp.getTransportInfo(stateRef)
    sender_ip = transportAddress[0]
    received_at = datetime.now(TZ)

    vars_list = [
        {"oid": str(oid), "value": val.prettyPrint()}
        for oid, val in varBinds
    ]

    # -----------------------------------------------------
    # BASIC ALARM EXTRACTION (SAFE DEFAULT LOGIC)
    # Replace later with Huawei OID mapping
    # -----------------------------------------------------
    alarm_code = vars_list[0]["oid"]
    description = vars_list[0]["value"]
    severity = "Critical"
    site = "UNKNOWN"
    device_type = "HUAWEI"
    device_time = received_at.isoformat()

    # Simple recovery detection
    state = "Recovery" if "clear" in description.lower() else "Fault"

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    # -----------------------------------------------------
    # STORE RAW TRAP (AUDIT TABLE)
    # -----------------------------------------------------
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

    # -----------------------------------------------------
    # 🔥 CORE ALARM LIFECYCLE FUNCTION
    # -----------------------------------------------------
    cur.execute(
        """
        SELECT process_alarm_row(
            %s, %s, %s, %s, %s, %s, %s, %s, %s
        )
        """,
        (
            received_at,   # p_received_at
            site,          # p_site
            device_type,   # p_device_type
            sender_ip,     # p_source
            alarm_code,    # p_alarm_code
            severity,      # p_severity
            description,   # p_description
            state,         # Fault | Recovery
            device_time,   # p_device_time
        )
    )

    conn.commit()
    cur.close()
    conn.close()

    print(f"[+] {state} alarm from {sender_ip}")

# =========================================================
# START RECEIVER
# =========================================================

ntfrcv.NotificationReceiver(snmpEngine, cbFun)

print(f"Listening for SNMP traps on {LISTEN_IP}:{LISTEN_PORT}")

snmpEngine.transportDispatcher.jobStarted(1)
snmpEngine.transportDispatcher.runDispatcher()
