# PostgreSQL SNMP Alarm Database

This repository documents the **PostgreSQL schema and logic** used for storing and processing **SNMP traps and alarms**. The database implements a classic **ACTIVE / HISTORICAL alarm model**, with core alarm-state logic handled inside PostgreSQL.

---

## Overview

The database is responsible for:

- Storing raw and parsed SNMP traps
- Maintaining **currently active alarms**
- Archiving **cleared alarms** into history
- Enforcing alarm uniqueness and consistency

Alarm state transitions are handled by a stored function:

```
process_alarm_row(...)
```

This design centralizes alarm logic and keeps external applications simple and stateless.

---

## Authentication & Access

### pg_hba.conf (Effective Rules)

The database uses secure authentication:

| Connection Type | Database | User | Auth Method |
|----------------|---------|------|-------------|
| local | all | postgres | peer |
| host | all | all | scram-sha-256 |
| local | replication | all | peer |
| host | replication | all | scram-sha-256 |

This allows:
- Passwordless local access for `postgres`
- SCRAM-SHA-256 authentication for application users (e.g. `snmpuser`)

---

## Database Objects

### Tables

#### 1. `traps`
Stores raw SNMP traps as they are received.

```sql
id          BIGINT PRIMARY KEY
received_at TIMESTAMP NOT NULL
sender      TEXT
raw         JSONB
parsed      JSONB
```

Purpose:
- Audit trail of all incoming traps
- Debugging and replay

---

#### 2. `active_alarms`
Stores **currently active alarms only**.

```sql
alarm_id    BIGINT PRIMARY KEY
first_seen  TIMESTAMP NOT NULL
last_seen   TIMESTAMP NOT NULL
site        TEXT
device_type TEXT
source      TEXT
alarm_code  TEXT
severity    TEXT
description TEXT
device_time TEXT
```

Indexes:

```sql
PRIMARY KEY (alarm_id)
UNIQUE (site, device_type, source, alarm_code)
```

Purpose:
- Real-time alarm view
- Enforces one active alarm per unique alarm key

---

#### 3. `historical_alarms`
Stores **cleared alarms** for long-term analysis.

```sql
alarm_id      BIGINT
first_seen    TIMESTAMP NOT NULL
last_seen     TIMESTAMP NOT NULL
recovery_time TIMESTAMP NOT NULL
site          TEXT
device_type   TEXT
source        TEXT
alarm_code    TEXT
severity      TEXT
description   TEXT
device_time   TEXT
```

Purpose:
- Alarm history and reporting
- SLA and MTTR calculations

---

## Core Alarm Logic

### Stored Function

```sql
process_alarm_row(
  p_received_at   TIMESTAMP,
  p_site          TEXT,
  p_device_type   TEXT,
  p_source        TEXT,
  p_alarm_code    TEXT,
  p_severity      TEXT,
  p_description   TEXT,
  p_state         TEXT,
  p_device_time   TEXT
)
RETURNS void
```

### Behavior

#### Alarm Raised (`ACTIVE` / `RAISE`)
- Insert new alarm into `active_alarms`
- Update `last_seen` if the alarm already exists

#### Alarm Cleared (`CLEAR` / `RECOVER`)
- Remove alarm from `active_alarms`
- Insert alarm into `historical_alarms`
- Set `recovery_time`

This guarantees:
- No cleared alarms remain active
- Full alarm lifecycle traceability

---

## Data Flow

```
Network Device
   ↓ SNMP Trap
Trap Receiver / Application
   ↓
INSERT INTO traps
   ↓
SELECT process_alarm_row(...)
   ↓
PostgreSQL
   ├── active_alarms
   └── historical_alarms
```

---

## Example Usage

### Raise an Alarm

```sql
SELECT process_alarm_row(
  now(),
  'SITE-A',
  'ROUTER',
  '10.21.10.18',
  'LINK_DOWN',
  'CRITICAL',
  'Uplink interface down',
  'ACTIVE',
  '2025-01-01 12:00:00'
);
```

### Clear an Alarm

```sql
SELECT process_alarm_row(
  now(),
  'SITE-A',
  'ROUTER',
  '10.21.10.18',
  'LINK_DOWN',
  'NORMAL',
  'Uplink interface restored',
  'CLEAR',
  '2025-01-01 12:05:00'
);
```

---

## Design Rationale

Why alarm logic is implemented in PostgreSQL:

- Single source of truth
- Transaction-safe state transitions
- Simplified application code
- Prevents race conditions
- Easy auditing and troubleshooting

---

## Operational Notes

- All tables were empty at last verification (clean state)
- External applications must call `process_alarm_row()` to manipulate alarms
- Direct inserts into `active_alarms` or `historical_alarms` are discouraged

---

## License

This database schema and logic are intended for internal or educational use.

