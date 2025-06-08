#!/bin/bash
set -e
source scripts/utils.sh

function usage {
  echo "Usage: $0 export -f <compose.yml> [-f <...>] [-o <output_dir>]"
  echo "Options:"
  echo "  -f <compose.yml>  Specify Docker Compose file (can be used multiple times)"
  echo "  -o <output_dir>   Specify output directory (default: ./offline_bundle_<timestamp>)"
  exit 1
}

if [[ "$1" != "export" ]]; then usage; fi
shift

COMPOSE_FILES=()
OUTPUT_DIR=""
while getopts "f:o:" opt; do
  case $opt in
    f) COMPOSE_FILES+=("$OPTARG");;
    o) OUTPUT_DIR="$OPTARG";;
    *) usage ;;
  esac
done

[[ ${#COMPOSE_FILES[@]} -ge 1 ]] || usage
PROJECT_DIR=$(pwd)

# Set default output directory if not specified
if [[ -z "$OUTPUT_DIR" ]]; then
  EXPORT_DIR="$PROJECT_DIR/offline_bundle_$(date +%s)"
else
  # Handle relative and absolute paths
  if [[ "$OUTPUT_DIR" = /* ]]; then
    EXPORT_DIR="$OUTPUT_DIR"
  else
    EXPORT_DIR="$PROJECT_DIR/$OUTPUT_DIR"
  fi
fi

echo "📁 Export directory: $EXPORT_DIR"
mkdir -p "$EXPORT_DIR/containers" "$EXPORT_DIR/volumes" "$EXPORT_DIR/project"

echo "📦 Exporting images → container snapshots"
local_containers=$(docker compose "${COMPOSE_FILES[@]/#/-f }" ps -q)
for cid in $local_containers; do
  name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's#/##')
  docker export "$cid" -o "$EXPORT_DIR/containers/${name}.tar"
done

echo "📂 Exporting mounted data"
for cid in $local_containers; do
  exports=$(docker inspect "$cid" | jq -r '.[0].Mounts[] | "\(.Type) \(.Source) \(.Destination)"')
  while read -r type src dst; do
    fname=$(sanitize "${name}_${dst}")
    if [[ "$type" == "bind" ]]; then
      cp -r "$src" "$EXPORT_DIR/volumes/$fname"
    else
      volpath=$(docker volume inspect "$(basename $src)" | jq -r '.[0].Mountpoint')
      cp -r "$volpath" "$EXPORT_DIR/volumes/$fname"
    fi
  done <<< "$exports"
done

echo "🧾 Collecting project files"
rsync -av --exclude offline_bundle_* . "$EXPORT_DIR/project/"

echo "✅ Export completed: $EXPORT_DIR"
