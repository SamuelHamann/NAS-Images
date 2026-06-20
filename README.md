# NAS-Images

## Services

### PostgreSQL (`postgres/`)

Lightweight, hardened **PostgreSQL 16 (alpine)** server shared across all
NAS apps. A single instance hosts multiple logical databases — one per
app — each with its own login role.

- **Image:** `postgres:16.4-alpine3.20` (pinned)
- **Port:** `127.0.0.1:5432` (loopback only; other stacks use the
  `postgres_net` docker network)
- **Volumes:** `postgres_data` (cluster files), `./initdb` (first-boot
  init scripts, read-only)
- **Init scripts mounted into the container** (one file per app, ordered):
  - `initdb/01-create-databases.sh` — creates one DB + owning role per
    entry in `POSTGRES_MULTIPLE_DATABASES`.
  - `initdb/02-init-whatsfordinner.sql` — schema for the
    **WhatsForDinner** app (recipes, ingredients, units, tags, pantry
    stock, cook history).
  - *(add `initdb/NN-init-<name>.sql` per new app — see
    [`postgres/README.md`](./postgres/README.md))*
- **Env vars:** see [`postgres/.env.example`](./postgres/.env.example).
- **Deploy:**
  ```bash
  cd postgres
  cp .env.example .env   # then fill in real passwords
  docker compose up -d
  ```
- **Details / security notes:** [`postgres/README.md`](./postgres/README.md)

### Home Assistant (`home-assistant/`)

Self-hosted **Home Assistant Core** — the home automation hub for the
NAS. State and configuration live in a bind-mounted `./config`
directory so they are easy to back up.

- **Image:** `ghcr.io/home-assistant/home-assistant:2025.12` (pinned)
- **Port:** `${HA_BIND_ADDR:-0.0.0.0}:${HA_BIND_PORT:-8123}` → `8123`
  (web UI / REST / WS API). Other stacks (e.g. a reverse proxy) can
  attach to the `home_assistant_net` network instead.
- **Volumes:** `./config` (bind, all HA state),
  `/etc/localtime` (bind, read-only),
  `/run/dbus` (optional bind for Bluetooth/Avahi, commented out).
- **Env vars:** see [`home-assistant/.env.example`](./home-assistant/.env.example)
  (`TZ`, `HA_BIND_ADDR`, `HA_BIND_PORT`).
- **Deploy:**
  ```bash
  cd home-assistant
  cp .env.example .env   # then edit TZ / bind address if needed
  docker compose up -d
  ```
  Then open `http://<nas-ip>:8123` and complete the onboarding wizard.
- **Hardware:** Zigbee / Z-Wave / Bluetooth dongles and mDNS-based
  discovery (Chromecast, HomeKit, Sonos…) are **opt-in** — see
  [`home-assistant/README.md`](./home-assistant/README.md).
- **Details / security notes:** [`home-assistant/README.md`](./home-assistant/README.md)
