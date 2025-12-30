#!/opt/pysnmp-venv/bin/python
# ==========================================================
# SNMP Trap Receiver with Alarm Lifecycle (PRODUCTION FIXED)
# ==========================================================

import json
from datetime import datetime
from zoneinfo import ZoneInfo
import psycopg2

from pysnmp.entity import engine, config
from pysnmp.carrier.asyncore.dgram import udp
from pysnmp.entity.rfc3413 import ntfrcv


# ==========================================================
# CONFIGURATION
# ==========================================================

TZ = ZoneInfo("Asia/Dhaka")

LISTEN_IP = "0.0.0.0"
LISTEN_PORT = 8899

DB_CONFIG = {
    "host": "localhost",
    "dbname": "snmptraps",
    "user": "snmpuser",
    "password": "toor",
}

SNMP_USER = "snmpuser"
AUTH_KEY = "Fiber@Dwdm@9800"
PRIV_KEY = "Fiber@Dwdm@9800"

HUAWEI_ENGINE_ID = b"\x80\x00\x13\x70\x01\xc0\xa8\x2a\x05"


# ==========================================================
# SNMP ENGINE SETUP (FIXED)
# ==========================================================

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

# ✅ REQUIRED FOR AUTHPRIV
config.addTargetParams(
    snmpEngine,
    "trap-creds",
    SNMP_USER,
    "authPriv"
)

config.addTransport(
    snmpEngine,
    udp.domainName,
    udp.UdpTransport().openServerMode((LISTEN_IP, LISTEN_PORT))
)

config.addContext(snmpEngine, "")


# ==========================================================
# HELPERS
# ==========================================================

def normalize_state(raw):
    if raw is None:
        return "Fault"

    raw = str(raw).strip().lower()
    if raw in ("0", "clear", "cleared", "normal", "recovery", "recover"):
        return "Recovery"
    return "Fault"


def get_value(vars_list, oid):
    for v in vars_list:
        if v["oid"] == oid:
            return v["value"]
    return None


def is_snmp_agent_trap(vars_list):
    for v in vars_list:
        if v["oid"] == "1.3.6.1.4.1.2011.2.15.1" and v["value"] == "SNMP Agent":
            return True
    return False


# ==========================================================
# TRAP CALLBACK
# ==========================================================

def cbFun(snmpEngine, stateRef, contextEngineId, contextName, varBinds, cbCtx):

    transportDomain, transportAddress = snmpEngine.msgAndPduDsp.getTransportInfo(stateRef)
    sender_ip = transportAddress[0]

    received_at = datetime.now(TZ).replace(tzinfo=None)

    vars_list = [{"oid": str(oid), "value": val.prettyPrint()} for oid, val in varBinds]

    if is_snmp_agent_trap(vars_list):
        print(f"[IGNORED] SNMP Agent trap from {sender_ip}")
        return

    site        = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.1.0")
    device_type = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.2.0")
    source      = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.3.0")
    description = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.6.0")
    severity    = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.7.0")
    raw_state   = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.10.0")
    alarm_code  = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.24.0")
    device_time = get_value(vars_list, "1.3.6.1.4.1.2011.2.15.1.7.1.5.0")

    state = normalize_state(raw_state)

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    try:
        # Store raw trap
        cur.execute("""
            INSERT INTO traps (received_at, sender, raw, parsed)
            VALUES (%s, %s, %s, %s)
        """, (
            received_at,
            sender_ip,
            json.dumps(vars_list),
            json.dumps(vars_list),
        ))

        # Alarm lifecycle (SAFE + CASTED)
        if all([site, device_type, source, alarm_code, state]):
            cur.execute("""
                SELECT process_alarm_row(
                    %s::timestamp,
                    %s::text,
                    %s::text,
                    %s::text,
                    %s::text,
                    %s::text,
                    %s::text,
                    %s::text,
                    %s::text
                )
            """, (
                received_at,
                site,
                device_type,
                source,
                alarm_code,
                severity,
                description,
                state,
                device_time,
            ))

        conn.commit()
        print(f"[OK] {state} | {alarm_code} | {site}")

    except Exception as e:
        conn.rollback()
        print("❌ DB ERROR:", e)

    finally:
        cur.close()
        conn.close()


# ==========================================================
# START LISTENER
# ==========================================================

ntfrcv.NotificationReceiver(snmpEngine, cbFun)

print(f"Listening for SNMP traps on {LISTEN_IP}:{LISTEN_PORT}")

try:
    snmpEngine.transportDispatcher.jobStarted(1)
    snmpEngine.transportDispatcher.runDispatcher()
except KeyboardInterrupt:
    print("Stopping trap receiver...")
    snmpEngine.transportDispatcher.closeDispatcher()
