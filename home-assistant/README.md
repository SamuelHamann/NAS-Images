# Home Assistant

Self-hosted **Home Assistant Core** for the NAS, running the official
container image. State and configuration are bind-mounted into
[`./config`](./config) so they are easy to back up alongside the rest
of the NAS data.

---

## What it is / why it's here

[Home Assistant](https://www.home-assistant.io/) is the home automation
hub that ties together every "smart" device on the network (lights,
sensors, media players, energy meters, etc.). Running it in a container
on the NAS keeps it close to the storage it relies on and lets it be
managed the same way as every other service in this repo.

## Image

- `ghcr.io/home-assistant/home-assistant:2025.12` — official image,
  pinned to a specific monthly release. Bumping the tag is an
  intentional, reviewable change (read the
  [HA release notes](https://www.home-assistant.io/blog/) first —
  breaking changes are common).

## Ports

| Host binding                                    | Container | Purpose                |
| ----------------------------------------------- | --------- | ---------------------- |
| `${HA_BIND_ADDR:-0.0.0.0}:${HA_BIND_PORT:-8123}` | `8123`    | Web UI / REST / WS API |

Other NAS stacks (e.g. a reverse proxy) can join the
`home_assistant_net` network and reach Home Assistant at
`home-assistant:8123` **without** going through the published host
port — see [*Reverse proxy*](#reverse-proxy) below.

## Volumes / data paths

| Mount                            | Path in container   | Stores                                                                                                          |
| -------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------- |
| `./config` (bind, read-write)    | `/config`           | `configuration.yaml`, automations, scripts, `secrets.yaml`, `home-assistant_v2.db` (history), `.storage/` (auth, devices, integrations…), `custom_components/`, logs, blueprints… |
| `/etc/localtime` (bind, ro)      | `/etc/localtime`    | Host timezone (display only)                                                                                    |
| `/run/dbus` (bind, ro)           | `/run/dbus`         | **Optional** — host D-Bus for Bluetooth / Avahi (commented out by default)                                      |

**Everything that matters lives under `./config`.** Back up that
directory and you can rebuild the stack anywhere.

## Required environment variables

All defined in [`.env.example`](./.env.example) — copy it to `.env` and
adjust to your environment.

| Variable        | Required | Purpose                                                                                  |
| --------------- | -------- | ---------------------------------------------------------------------------------------- |
| `TZ`            | no       | IANA timezone (default `Etc/UTC`). Used for logs, automations, schedules.                |
| `HA_BIND_ADDR`  | no       | Host interface the web UI is published on (default `0.0.0.0`). Use `127.0.0.1` behind a reverse proxy. |
| `HA_BIND_PORT`  | no       | Host port for the web UI (default `8123`). The container always listens on `8123`.       |

## How to deploy

```bash
cd home-assistant
cp .env.example .env        # then edit TZ / bind address if needed
docker compose up -d
docker compose logs -f      # watch the first-boot setup
```

Then open `http://<nas-ip>:8123` in a browser and complete the
onboarding wizard. The owner account you create there is HA's local
admin — **not** the same as any system user.

Verify:

```bash
docker compose ps
docker compose exec home-assistant ha core info   # if the `ha` CLI is present
curl -fsS http://127.0.0.1:8123/ >/dev/null && echo "HA is up"
```

## Permissions

The HA container runs as **root** inside the container (required by
its s6-overlay init — see the security note in `compose.yaml`). Files
written into `./config` on the host will therefore be owned by `root`.
That is normal and expected for this image; do not `chown` them to
another user or HA will refuse to start.

## Hardware integrations (opt-in)

The default configuration is "software only" — perfect for cloud
integrations (Spotify, weather, calendars…) and LAN/IP devices
(printers, media players reached over the network, etc.). To use
local-radio hardware, opt in by editing `compose.yaml`:

- **Zigbee / Z-Wave / Matter Thread USB stick** — uncomment the
  `devices:` block and point it at the dongle's stable
  `/dev/serial/by-id/...` path. Avoid `/dev/ttyUSB0`: USB numbering
  is not stable across reboots.
- **Bluetooth (BlueZ on the host)** — uncomment the `- /run/dbus:/run/dbus:ro`
  volume so HA can talk to the host's BlueZ daemon.
- **mDNS-based discovery (Chromecast, HomeKit, Sonos, Hue bridges,
  AirPlay…)** — bridge networking blocks multicast traffic by design.
  Either:
  - install / configure HA's "Network" integration to point at the
    specific device IPs (works for most things), **or**
  - switch the service to `network_mode: host` (more compatible, less
    isolated — drop the `ports:` and `networks:` blocks if you do).

## Reverse proxy

To put HA behind a reverse proxy (Caddy, Nginx Proxy Manager, Traefik…)
running in a sibling stack:

1. In `.env`, set `HA_BIND_ADDR=127.0.0.1` so port `8123` is no longer
   reachable from the LAN.
2. In the proxy's compose file, attach to this stack's network:

   ```yaml
   services:
     proxy:
       # ...
       networks:
         - home_assistant_net

   networks:
     home_assistant_net:
       external: true   # created by the home-assistant stack
   ```

3. Forward the proxy's TLS vhost to `http://home-assistant:8123`.
4. Add the proxy's IP / hostname to HA's `http:` block in
   `configuration.yaml` so HA trusts the `X-Forwarded-For` headers:

   ```yaml
   http:
     use_x_forwarded_for: true
     trusted_proxies:
       - 172.16.0.0/12   # docker bridge range
   ```

## Backups

`./config` contains literally everything — back it up regularly. Two
common patterns:

- **Filesystem snapshot** of the `home-assistant/config` directory as
  part of the NAS's normal backup job. Stop the container first
  (`docker compose stop`) or accept a slightly inconsistent SQLite
  history database.
- **HA's built-in backups** — *Settings → System → Backups* in the UI
  creates a `.tar` archive in `./config/backups/` that includes a
  consistent snapshot of the database. The Core container does not run
  scheduled backups by itself, so trigger them from an automation.

## Security notes

- **Secrets** never leave `.env` (git-ignored). HA's own secrets live
  in `config/secrets.yaml` — also ignored via the `config/*` rule.
- **Image pinning** to a specific monthly release tag — never
  `latest` / `stable`. Bumps are deliberate.
- **`no-new-privileges:true`** prevents anything inside the container
  from escalating beyond what the entrypoint started with.
- **No `privileged: true`** by default. The official HA example uses
  it; we don't, because it grants full host access. Only opt in if you
  pass through hardware that genuinely needs it.
- **No `network_mode: host`** by default — bridge networking gives HA
  its own network namespace and avoids exposing every container port
  on the host.
- **Capabilities and user are intentionally left at the image's
  defaults** — see the long comment in `compose.yaml`. The HA image
  requires root inside the container; dropping all capabilities breaks
  the s6 init.
- **Bind address** is configurable so you can lock HA to a specific
  LAN interface or to loopback when fronted by a reverse proxy.
- **Resource limits** (`mem_limit: 2g`, `cpus: 2.0`) protect the rest
  of the NAS from a runaway integration.
- **Log rotation** (`json-file`, 5 × 10 MB) caps disk usage from
  container logs.
- **Strong onboarding password** is on you — HA's first user is its
  superuser. Enable MFA from *Profile → Multi-factor authentication*
  immediately after first login.
- **HTTPS** — terminate TLS at a reverse proxy (see above). Don't
  expose HA's plain-HTTP `8123` to the public internet.
