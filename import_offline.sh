#!/bin/bash
set -e
source scripts/utils.sh

BUNDLE="$(pwd)"
[[ -d "$BUNDLE/containers" && -d "$BUNDLE/volumes" && -d "$BUNDLE/project" ]] \
  || { echo "Error: No correctly structured offline_bundle found"; exit 1; }

echo "🔧 Importing container images as local images"
for tar in containers/*.tar; do
  name=$(basename "$tar" .tar)
  docker import "$tar" "${name}:offline"
done

echo "📌 Restoring mounted directories"
RESTORE_PATH="/offline_volumes"
mkdir -p "$RESTORE_PATH"
cp -r volumes/* "$RESTORE_PATH/"

echo "📝 Patching docker-compose.yml → docker-compose.patched.yml"
scripts/patch_compose.sh "project/docker-compose.yml" "$RESTORE_PATH"

echo "🚀 Starting services"
cd project
docker compose -f docker-compose.patched.yml up -d

echo "✅ Recovery successful, original file backed up as docker-compose.yml.bak"
