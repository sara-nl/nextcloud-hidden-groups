#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Hidden groups contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

# Starts the official Nextcloud Docker image, installs the app from this checkout
# and runs the end-to-end test against it. The container is removed afterwards.
#
# usage: tests/e2e/run-docker.sh <image tag, e.g. 35 or latest> [port]
#
# Build the frontend first (npm ci && npm run build).
# Set FORCE_ENABLE=1 to enable the app on a Nextcloud version newer than max-version in info.xml.
set -euo pipefail
TAG=${1:?usage: $0 <image tag, e.g. 35 or latest> [port]}
PORT=${2:-8080}
APP_DIR=$(cd "$(dirname "$0")/../.." && pwd)
CONTAINER=hidden-groups-e2e-$TAG
IMAGE=nextcloud:$TAG-apache
if [ "$TAG" = latest ]; then
	IMAGE=nextcloud:apache
fi

if [ ! -f "$APP_DIR/js/hidden_groups-main.mjs" ]; then
	echo "Build the frontend first: npm ci && npm run build" >&2
	exit 1
fi

docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
trap 'docker rm -f "$CONTAINER" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$CONTAINER" -p "127.0.0.1:$PORT:80" \
	-e SQLITE_DATABASE=nextcloud \
	-e NEXTCLOUD_ADMIN_USER=admin \
	-e NEXTCLOUD_ADMIN_PASSWORD="$(head -c 24 /dev/urandom | base64)" \
	-e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
	"$IMAGE" >/dev/null

echo "Waiting for Nextcloud ($TAG) to be installed..."
for _ in $(seq 1 120); do
	if curl -s "http://localhost:$PORT/status.php" | grep -q '"installed":true'; then
		break
	fi
	sleep 2
done
curl -s "http://localhost:$PORT/status.php" | grep -q '"installed":true' || { docker logs "$CONTAINER" | tail -20; exit 1; }

docker exec "$CONTAINER" mkdir -p /var/www/html/custom_apps/hidden_groups
tar -C "$APP_DIR" -cf - appinfo css js l10n lib templates |
	docker exec -i "$CONTAINER" tar -C /var/www/html/custom_apps/hidden_groups -xf -
docker exec "$CONTAINER" chown -R www-data:www-data /var/www/html/custom_apps/hidden_groups
docker exec -u www-data "$CONTAINER" php occ app:enable ${FORCE_ENABLE:+--force} hidden_groups

status=0
"$APP_DIR/tests/e2e/e2e.sh" "http://localhost:$PORT" docker "$CONTAINER" || status=$?

echo "== Nextcloud log (warnings and errors)"
docker exec "$CONTAINER" sh -c 'cat /var/www/html/data/nextcloud.log 2>/dev/null' || true
exit $status
