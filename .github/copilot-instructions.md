# Copilot Instructions — NAS-Images

## Repository purpose
This repository stores all container images and configurations (mostly **Docker
Compose**) for a **personal NAS**. Each service/app lives here so it can be
version-controlled, reviewed, and redeployed reliably.

## Core principles (always apply)
1. **Security first** — every configuration must default to secure settings.
2. **Explain everything** — every Compose file must include clear explanations
   of what each setting does and why it is set that way.
3. **Document as we grow** — whenever an image/service is added or changed, the
   `README.md` must be updated to reflect it. This is important and not optional.

## Secure configuration conventions
When writing or editing `docker-compose.yml` (or `compose.yaml`) files:

- **No secrets in Git.** Never hard-code passwords, API keys, or tokens. Use a
  `.env` file (git-ignored) referenced via `${VAR}`, and provide a committed
  `.env.example` documenting required variables.
- **Pin image versions.** Avoid `latest`; use explicit tags/digests for
  reproducible, auditable deployments.
- **Least privilege:**
  - Set `restart: unless-stopped` unless a reason exists not to.
  - Drop capabilities (`cap_drop: [ALL]`) and add back only what's needed.
  - Add `security_opt: ["no-new-privileges:true"]`.
  - Run as a non-root user (`user: "UID:GID"` / `PUID`/`PGID`) where supported.
  - Use `read_only: true` filesystems with explicit `tmpfs`/volumes when viable.
- **Networking:** only expose ports that are required. Prefer binding to a
  specific interface (e.g. `127.0.0.1:PORT:PORT`) and use internal Docker
  networks for service-to-service traffic. Put public-facing services behind a
  reverse proxy with TLS.
- **Persistence:** use named volumes or explicit bind mounts; keep mount paths
  consistent and documented.
- **Health & limits:** add `healthcheck` blocks and resource limits
  (`mem_limit`, `cpus`) where appropriate.

## Per-service documentation requirement
Every service should be self-explanatory. Use inline comments in the Compose
file to explain non-obvious settings, and document each service in the README.

## README maintenance (required)
Keep `README.md` current. For each service, document at minimum:
- **What it is / why it's here** (one or two lines).
- **Ports** exposed and what they're for.
- **Volumes / data paths** and what they store.
- **Required environment variables** (referencing `.env.example`).
- **How to deploy** (e.g. `docker compose up -d`) and any first-run steps.
- **Security notes** specific to the service.

> Reminder for the agent: if you add or modify a service, update `README.md` in
> the same change. Do not consider the task complete until the docs match.
