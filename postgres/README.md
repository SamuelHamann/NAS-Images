# PostgreSQL

Lightweight, shared **PostgreSQL 16 (alpine)** instance for the NAS. One
server process hosts several logical databases — one per app — each with
its own login role for SQL-level isolation.

Other NAS stacks join the shared docker network `postgres_net` and reach
the server at `postgres:5432` without exposing any host port.

---

## What it is / why it's here

A single small, hardened postgres container avoids running one database
engine per app. Apps stay isolated because each one only has credentials
for *its own* database + role.

## Image

- `postgres:16.4-alpine3.20` — pinned minor + alpine variant for a small,
  reproducible image (~85 MB).

## Ports

| Host binding                     | Container | Purpose                                 |
| ------------------------------- | --------- | --------------------------------------- |
| `127.0.0.1:${POSTGRES_BIND_PORT:-5432}` | `5432`    | Local admin access only (psql, tunnels) |

The port is bound to **loopback only**. Apps on the same NAS talk to
postgres over the internal docker network — they do not need this port.

## Volumes / data paths

| Volume / mount                | Path in container                  | Stores                                  |
| ----------------------------- | ---------------------------------- | --------------------------------------- |
| `postgres_data` (named)       | `/var/lib/postgresql/data`         | Cluster files, WAL, configuration       |
| `./initdb` (bind, read-only)  | `/docker-entrypoint-initdb.d`      | First-boot init scripts (see below)     |
| tmpfs                         | `/tmp`, `/run/postgresql`          | Volatile sockets / scratch              |

`PGDATA` is set to `/var/lib/postgresql/data/pgdata` so future sibling
mounts (e.g. backups) don't clash with the data directory.

## Required environment variables

All defined in [`.env.example`](./.env.example) — copy it to `.env` and
fill in real values.

| Variable                          | Required | Purpose                                                              |
| --------------------------------- | -------- | -------------------------------------------------------------------- |
| `POSTGRES_USER`                   | yes      | Superuser name                                                       |
| `POSTGRES_PASSWORD`               | yes      | Superuser password (use `openssl rand -base64 32`)                   |
| `POSTGRES_DB`                     | no       | Default maintenance database (default `postgres`)                    |
| `POSTGRES_MULTIPLE_DATABASES`     | no       | Comma-separated list of per-app databases to create on first boot    |
| `POSTGRES_<NAME>_PASSWORD`        | no\*     | Password for each role created from the list above (uppercased name) |
| `POSTGRES_BIND_PORT`              | no       | Host loopback port (default `5432`)                                  |

\* If missing, the init script falls back to `POSTGRES_PASSWORD` and
prints a warning. Always set a dedicated password per app on the NAS.

## Init scripts (injected into the image)

The official postgres entrypoint runs every file in
`/docker-entrypoint-initdb.d/` in alphabetical order, **only on the very
first boot** (when `PGDATA` is empty).

There is **one schema file per app**, numbered so they run after the
database-creation step. Adding a new app means adding a new file rather
than editing an existing one — keeps reviews and rollbacks scoped to a
single service.

| File                                       | Type | What it does                                                                                  |
| ------------------------------------------ | ---- | --------------------------------------------------------------------------------------------- |
| `initdb/01-create-databases.sh`            | sh   | Reads `POSTGRES_MULTIPLE_DATABASES`; for each entry creates a login role and a DB it owns.    |
| `initdb/02-init-whatsfordinner.sql`        | sql  | Schema for the **WhatsForDinner** app (recipes, ingredients, units, tags, pantry stock).      |

To add a new database:

1. Append its name to `POSTGRES_MULTIPLE_DATABASES` in `.env`.
2. Add a `POSTGRES_<NAME>_PASSWORD=…` entry in `.env`.
3. Create a new `initdb/NN-init-<name>.sql` (next free `NN`, e.g. `03-`)
   that `\connect`s to the app database, creates its tables, and
   `ALTER … OWNER TO <name>;` every table **and sequence**.
4. Either start from a clean volume (first deploy) **or** apply the new
   file manually against the running server (see *Re-running init*
   below).

## How to deploy

```bash
cd postgres
cp .env.example .env        # then edit .env and set real passwords
docker compose up -d
docker compose logs -f      # watch the init scripts on first boot
```

Verify:

```bash
docker compose exec postgres sh -lc 'pg_isready -U "$POSTGRES_USER"'
docker compose exec postgres sh -lc 'psql -U "$POSTGRES_USER" -c "\\l"'
```

### Letting another stack use this server

In the other stack's compose file:

```yaml
services:
  myapp:
    # ...
    environment:
      DATABASE_URL: postgres://app1:${APP1_DB_PASSWORD}@postgres:5432/app1
    networks:
      - postgres_net

networks:
  postgres_net:
    external: true   # created by the postgres stack
```

### Re-running init scripts on an existing cluster

The entrypoint **does not** re-run `/docker-entrypoint-initdb.d/` once
`PGDATA` is populated. To add a database later, either:

- run the shell script manually:
  ```bash
  docker compose exec -e POSTGRES_MULTIPLE_DATABASES=newdb postgres \
    bash /docker-entrypoint-initdb.d/01-create-databases.sh
  ```
- or apply SQL directly:
  ```bash
docker compose exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d postgres' < my-change.sql

## Security notes

- **Secrets** live only in `.env` (git-ignored); `compose.yaml` uses
  `${VAR:?}` so the stack refuses to start with missing credentials.
- **SCRAM-SHA-256** is forced for every role via `POSTGRES_INITDB_ARGS`
  on first boot — no MD5 fallback.
- **Capabilities**: dropped to `ALL`, only `CHOWN`, `DAC_READ_SEARCH`,
  `FOWNER`, `SETUID`, `SETGID` are added back (needed by the entrypoint
  to chown PGDATA and `su-exec` to the unprivileged `postgres` user).
- **`no-new-privileges:true`** blocks setuid escalations inside the
  container.
- **Loopback-only port binding** — postgres is not reachable from the LAN
  unless you expose it via a reverse proxy or SSH tunnel.
- **Resource limits** (`mem_limit`, `cpus`) protect the rest of the NAS
  from a runaway query.
- **Log rotation** (`json-file`, 5 × 10 MB) prevents log files from
  filling the disk.
- **Backups are NOT included** in this stack — add a sidecar (e.g.
  `pg_dump` cron, or `pgbackrest`) before storing anything important.
