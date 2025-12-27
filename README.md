# SNMP Trap Receiver

## 🔹 Step 1 — Install Required Software

Run the following commands in your terminal:

```bash
sudo apt update
sudo apt install -y python3-pip postgresql postgresql-contrib
pip3 install pysnmp psycopg2-binary

✔ What This Installs

pysnmp — Receives SNMP traps

PostgreSQL — Database backend

psycopg2-binary — Python ↔ PostgreSQL adapter


🔹 Step 2 — Create PostgreSQL Database

Enter the PostgreSQL shell as the postgres user:

sudo -u postgres psql


Then run the following commands one by one:

CREATE DATABASE snmptraps;

CREATE USER snmpuser WITH PASSWORD 'toor';

ALTER ROLE snmpuser SET client_encoding TO 'utf8';
ALTER ROLE snmpuser SET default_transaction_isolation TO 'read committed';
ALTER ROLE snmpuser SET timezone TO 'Asia/Dhaka';

GRANT ALL PRIVILEGES ON DATABASE snmptraps TO snmpuser;


Exit the PostgreSQL shell:

\q

✅ Database Details (Summary)
Item	Value
Database	snmptraps
User	snmpuser
Password	toor
Timezone	Asia/Dhaka
