#!/bin/bash
# =============================================================================
# 01-create-databases.sh
# -----------------------------------------------------------------------------
# Runs ONCE, the very first time the postgres data directory is empty,
# courtesy of the official postgres image's `docker-entrypoint.sh` which
# executes every *.sh / *.sql in /docker-entrypoint-initdb.d/ in
# alphabetical order while the server is up on a local socket.
#
# For every entry in $POSTGRES_MULTIPLE_DATABASES (comma-separated), we
# create:
#   * a login role named <entry>, with password from
#     POSTGRES_<UPPER_ENTRY>_PASSWORD (fallback: $POSTGRES_PASSWORD)
#   * a database  named <entry>, owned by that role
#
# Re-running the script is safe: existence is checked against pg_roles /
# pg_database before each CREATE.
# =============================================================================

set -euo pipefail

if [ -z "${POSTGRES_MULTIPLE_DATABASES:-}" ]; then
  echo "[initdb] POSTGRES_MULTIPLE_DATABASES is empty — nothing to do."
  exit 0
fi

create_db_and_role() {
  local name="$1"

  # Uppercase + replace dashes with underscores so the env var name is
  # always a valid shell identifier (e.g. `my-app` -> MY_APP).
  local upper
  upper="$(echo "$name" | tr '[:lower:]-' '[:upper:]_')"
  local pw_var="POSTGRES_${upper}_PASSWORD"
  local password="${!pw_var:-$POSTGRES_PASSWORD}"

  if [ "$password" = "$POSTGRES_PASSWORD" ]; then
    echo "[initdb] WARN: '$name' is using the superuser password " \
         "(set $pw_var in .env to give it its own)."
  fi

  echo "[initdb] Ensuring role and database '$name' exist…"

  # Note: we use a heredoc with literal `'$password'` interpolation in
  # shell BEFORE psql sees it — the password value itself must therefore
  # be free of single quotes. Generated passwords from `openssl rand
  # -base64 N` satisfy that.
  psql -v ON_ERROR_STOP=1 \
       --username "$POSTGRES_USER" \
       --dbname   "$POSTGRES_DB" <<-SQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$name') THEN
        CREATE ROLE "$name" LOGIN PASSWORD '$password';
      END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE "$name" OWNER "$name"'
     WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$name')\gexec

    GRANT ALL PRIVILEGES ON DATABASE "$name" TO "$name";
SQL
}

IFS=',' read -ra DBS <<< "$POSTGRES_MULTIPLE_DATABASES"
for db in "${DBS[@]}"; do
  # Trim surrounding whitespace so `a, b , c` works as expected.
  db_trimmed="$(echo "$db" | xargs)"
  [ -z "$db_trimmed" ] && continue
  create_db_and_role "$db_trimmed"
done

echo "[initdb] All requested databases are ready."
