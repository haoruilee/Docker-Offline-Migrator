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
# Build compose file arguments properly
COMPOSE_ARGS=()
for file in "${COMPOSE_FILES[@]}"; do
  COMPOSE_ARGS+=("-f" "$file")
done

local_containers=$(docker compose "${COMPOSE_ARGS[@]}" ps -q)

# Get unique images from running containers
echo "🔍 Identifying images used by containers..."
declare -A container_images
for cid in $local_containers; do
  name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's#/##')
  image=$(docker inspect --format '{{.Config.Image}}' "$cid")
  container_images["$name"]="$image"
  echo "  📦 Container: $name → Image: $image"
done

# Export images (not container snapshots)
echo "💾 Exporting Docker images..."
for name in "${!container_images[@]}"; do
  image="${container_images[$name]}"
  echo "  Saving: $image → $EXPORT_DIR/containers/${name}.tar"
  docker save "$image" -o "$EXPORT_DIR/containers/${name}.tar"
done

echo "📂 Exporting mounted data"
for cid in $local_containers; do
  name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's#/##')
  
  exports=$(docker inspect "$cid" | jq -r '.[0].Mounts[] | "\(.Type) \(.Source) \(.Destination)"')
  
  while read -r type src dst; do
    # Skip empty lines
    [[ -z "$type" || -z "$src" || -z "$dst" ]] && continue
    
    fname=$(sanitize "${name}_${dst}")
    
    if [[ "$type" == "bind" ]]; then
      if [[ -e "$src" ]]; then
        echo "📁 Copying bind mount: $src → $EXPORT_DIR/volumes/$fname"
        if cp -r "$src" "$EXPORT_DIR/volumes/$fname" 2>/dev/null; then
          echo "✅ Bind mount copied successfully"
        else
          echo "⚠️  Warning: Some files in bind mount could not be copied (permission issues)"
          # Try with sudo if available
          if command -v sudo >/dev/null 2>&1; then
            echo "🔄 Trying with sudo..."
            if sudo cp -r "$src" "$EXPORT_DIR/volumes/$fname" 2>/dev/null; then
              echo "✅ Copied with sudo"
            else
              echo "❌ Even sudo copy failed - skipping problematic files"
            fi
          fi
        fi
      else
        echo "⚠️  Warning: Bind mount source not found: $src"
      fi
    elif [[ "$type" == "volume" ]]; then
      # Extract volume name from source path - handle Docker's volume path structure
      if [[ "$src" =~ /data/docker/volumes/([^/]+)/_data$ ]]; then
        vol_name="${BASH_REMATCH[1]}"
      else
        vol_name=$(basename "$src")
      fi
      
      if docker volume inspect "$vol_name" >/dev/null 2>&1; then
        volpath=$(docker volume inspect "$vol_name" | jq -r '.[0].Mountpoint')
        if [[ -n "$volpath" && "$volpath" != "null" ]]; then
          echo "📦 Copying volume: $vol_name ($volpath) → $EXPORT_DIR/volumes/$fname"
          if cp -r "$volpath" "$EXPORT_DIR/volumes/$fname" 2>/dev/null; then
            echo "✅ Volume copied successfully"
          else
            echo "⚠️  Warning: Some files in volume $vol_name could not be copied (permission issues)"
            # Try with sudo if available
            if command -v sudo >/dev/null 2>&1; then
              echo "🔄 Trying with sudo..."
              sudo cp -r "$volpath" "$EXPORT_DIR/volumes/$fname" 2>/dev/null || echo "❌ Sudo copy also failed"
            fi
          fi
        else
          echo "⚠️  Warning: Could not get mountpoint for volume: $vol_name"
        fi
      else
        echo "⚠️  Warning: Volume not found: $vol_name"
      fi
    fi
  done <<< "$exports"
done

echo "🧾 Collecting project files"
# Determine the project directory from the first compose file
FIRST_COMPOSE_FILE="${COMPOSE_FILES[0]}"
if [[ "$FIRST_COMPOSE_FILE" = /* ]]; then
  # Absolute path - get directory
  COMPOSE_PROJECT_DIR="$(dirname "$FIRST_COMPOSE_FILE")"
else
  # Relative path - resolve from current directory
  COMPOSE_PROJECT_DIR="$(cd "$(dirname "$FIRST_COMPOSE_FILE")" && pwd)"
fi

echo "📁 Project directory: $COMPOSE_PROJECT_DIR"
echo "📋 Copying project files..."

# Copy all compose files to project directory
for compose_file in "${COMPOSE_FILES[@]}"; do
  if [[ -f "$compose_file" ]]; then
    compose_basename="$(basename "$compose_file")"
    echo "  📄 Copying: $compose_basename"
    cp "$compose_file" "$EXPORT_DIR/project/"
  fi
done

# Copy other project files from the compose directory
echo "  📂 Copying additional project files from: $COMPOSE_PROJECT_DIR"
rsync -av --exclude offline_bundle_* \
  --exclude "*.tar" \
  --exclude "volumes" \
  "$COMPOSE_PROJECT_DIR/" "$EXPORT_DIR/project/" || echo "⚠️  Warning: Some project files could not be copied"

echo "✅ Export completed: $EXPORT_DIR"
