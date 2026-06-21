# 1. Stop the container
docker compose -f /volume1/docker/postgres/compose.yaml down

# 2. Wipe any partial/broken pgdata from previous failed starts
sudo rm -rf /volume1/docker/postgres/data/pgdata

# 3. Give UID 1000 ownership of the data directory
sudo chown -R 1000:1000 /volume1/docker/postgres/data
sudo chmod 700 /volume1/docker/postgres/data

# 4. Start fresh
docker compose -f /volume1/docker/postgres/compose.yaml up -d
docker compose -f /volume1/docker/postgres/compose.yaml logs -f


