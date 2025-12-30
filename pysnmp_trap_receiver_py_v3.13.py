#!/usr/bin/env python3
import os
import json
from datetime import datetime
from zoneinfo import ZoneInfo

import psycopg2
from pysnmp.entity import engine, config
from pysnmp.carrier.asyncio.dgram import udp
from pysnmp.entity.rfc3413 import ntfrcv

# =========================================================
# STRICT ENVIRONMENT VALIDATION
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
    raise RuntimeError(f"Missing required env vars: {', '.join(missing)}")

# =========================================================
# TIMEZONE
# =========================================================
TZ = ZoneInfo("Asia/Dhaka")

# =========================================================
# DATABASE CONFIG
# =========================================================
DB_CONFIG = {
    "host": os.environ["DB_HOST"],
    "port": int(os.environ["DB_PORT"]),
    "dbname": os.environ["DB_NAME"],
    "user": os.environ["DB_USER"],
    "password": os.environ["DB_PASS"],
}

# =========================================================
# SNMP LISTENER CONFIG
# =========================================================
LISTEN_IP = "0.0.0.0"
LISTEN_PORT = int(os.environ["SNMP_PORT"])

# =========================================================
# SNMPv3 SECURITY CONFIG
# =========================================================
SNMP_USER = "snmpuser"
AUTH_KEY = "Fiber@Dwdm@9800"
PRIV_KEY = "Fiber@Dwdm@9800"

snmpEngine = engine.SnmpEngine()

# ---- V3 USER (NEW API) ----
config.add_v3_user(
    snmpEngine,
    SNMP_USER,
    config.USM_AUTH_HMAC192_SHA256,
    AUTH_KEY,
    config.USM_PRIV_CFB128_AES,
    PRIV_KEY,
)

# ---- TRANSPORT (NEW API) ----
config.add_transport(
    snmpEngine,
    udp.DOMAIN_NAME,
    udp.UdpTransport().open_server_mode((LISTEN_IP, LISTEN_PORT)),
)

# =========================================================
# TRAP CALLBACK
# =========================================================
def cbFun(snmpEngine, stateRef, contextEngineId, contextName, varBinds, cbCtx=None):
    _, transportAddress = snmpEngine.msgAndPduDsp.getTransportInfo(stateRef)

    sender_ip = transportAddress[0]
    received_at = datetime.now(TZ)

    vars_list = [
        {"oid": str(oid), "value": val.prettyPrint()}
        for oid, val in varBinds
    ]

    alarm_code = vars_list[0]["oid"]
    description = vars_list[0]["value"]

    severity = "Critical"
    site = "UNKNOWN"
    device_type = "HUAWEI"
    device_time = received_at.isoformat()
    state = "Recovery" if "clear" in description.lower() else "Fault"

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
        ),
    )

    cur.execute(
        """
        SELECT process_alarm_row(
            %s,%s,%s,%s,%s,%s,%s,%s,%s
        )
        """,
        (
            received_at,
            site,
            device_type,
            sender_ip,
            alarm_code,
            severity,
            description,
            state,
            device_time,
        ),
    )

    conn.commit()
    cur.close()
    conn.close()

    print(f"[+] {state} alarm from {sender_ip}")

# =========================================================
# START RECEIVER (NO DEPRECATIONS)
# =========================================================
ntfrcv.NotificationReceiver(snmpEngine, cbFun)

print(f"Listening for SNMP traps on {LISTEN_IP}:{LISTEN_PORT}")

snmpEngine.transport_dispatcher.job_started(1)

try:
    snmpEngine.transport_dispatcher.run_dispatcher()
except KeyboardInterrupt:
    print("Stopping SNMP trap receiver...")
finally:
    snmpEngine.transport_dispatcher.close_dispatcher()
