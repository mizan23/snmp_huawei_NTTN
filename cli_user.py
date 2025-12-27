#!/usr/bin/env python3
import psycopg2
import argparse

DB_CONFIG = {
    "host": "localhost",
    "dbname": "snmptraps",
    "user": "grafana_user",
    "password": "toor",
}

def decode(desc):
    if desc and desc.startswith("0x"):
        try:
            return bytes.fromhex(desc[2:]).decode("utf-8", errors="replace")
        except:
            return desc
    return desc or ""

def print_rows(rows, mode):
    for r in rows:
        print("=" * 100)
        if mode == "active":
            print(f"Alarm ID   : {r[0]}")
            print(f"First Seen : {r[1]}")
            print(f"Last Seen  : {r[2]}")
            print(f"Site       : {r[3]}")
            print(f"Device     : {r[4]}")
            print(f"Source     : {r[5]}")
            print(f"Severity   : {r[6]}")
            print(f"Alarm Code : {r[7]}")
            print("Description:\n", decode(r[8]))
        else:
            print(f"Alarm ID    : {r[0]}")
            print(f"Recovered At: {r[3]}")
            print(f"Site        : {r[4]}")
            print(f"Severity    : {r[7]}")
            print(f"Alarm Code  : {r[8]}")
            print("Description:\n", decode(r[9]))
        print("=" * 100)

def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    sub.add_parser("active")
    sub.add_parser("history")
    args = parser.parse_args()

    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    if args.mode == "active":
        cur.execute("SELECT alarm_id, first_seen, last_seen, site, device_type, source, severity, alarm_code, description FROM active_alarms ORDER BY last_seen DESC")
    else:
        cur.execute("SELECT alarm_id, first_seen, last_seen, recovery_time, site, device_type, source, severity, alarm_code, description FROM historical_alarms ORDER BY recovery_time DESC")

    print_rows(cur.fetchall(), args.mode)
    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
