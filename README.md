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
    stock).
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
