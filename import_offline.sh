#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/utils.sh"

function usage {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -f <compose.yml>     Specify compose file in project/ (default: docker-compose.yml)"
  echo "  -r <restore_path>    Specify restore path for volumes (default: /offline_volumes)"
  echo "  -p <project_name>    Specify project name prefix for containers (default: auto-detect)"
  echo "  --dry-run           Only import images and prepare files, don't start services"
  echo "  --verify            Verify bundle structure and show what would be imported"
  echo "  -h, --help          Show this help message"
  exit 1
}

# Default values
COMPOSE_FILE="docker-compose.yml"
RESTORE_PATH="/offline_volumes"
PROJECT_NAME=""
DRY_RUN=false
VERIFY_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -f)
      COMPOSE_FILE="$2"
      shift 2
      ;;
    -r)
      RESTORE_PATH="$2"
      shift 2
      ;;
    -p)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verify)
      VERIFY_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

BUNDLE="$(pwd)"
[[ -d "$BUNDLE/containers" && -d "$BUNDLE/volumes" && -d "$BUNDLE/project" ]] \
  || { echo "Error: No correctly structured offline_bundle found"; exit 1; }

echo "📋 Bundle verification:"
echo "  - Containers: $(ls containers/*.tar 2>/dev/null | wc -l) files"
echo "  - Volumes: $(ls volumes/ 2>/dev/null | wc -l) directories"
echo "  - Compose file: project/$COMPOSE_FILE"
echo "  - Restore path: $RESTORE_PATH"

if [[ "$VERIFY_ONLY" == true ]]; then
  echo ""
  echo "🔍 Container snapshots:"
  for tar in containers/*.tar; do
    [[ -f "$tar" ]] && echo "  - $(basename "$tar" .tar)"
  done
  
  echo ""
  echo "📂 Volume backups:"
  for vol in volumes/*/; do
    [[ -d "$vol" ]] && echo "  - $(basename "$vol")"
  done
  
  echo ""
  echo "✅ Verification complete. Use without --verify to proceed with import."
  exit 0
fi

if [[ ! -f "project/$COMPOSE_FILE" ]]; then
  echo "Error: Compose file project/$COMPOSE_FILE not found"
  echo "Available files in project/:"
  ls project/ | grep -E '\.(yml|yaml)$' || echo "  No compose files found"
  exit 1
fi

echo "🔧 Importing container images as local images"
for tar in containers/*.tar; do
  [[ -f "$tar" ]] || continue
  name=$(basename "$tar" .tar)
  
  echo "  Loading: $tar"
  docker load -i "$tar"
  
  # Get the loaded image name and tag it with our naming convention
  loaded_image=$(docker load -i "$tar" 2>/dev/null | grep "Loaded image:" | sed 's/Loaded image: //')
  if [[ -n "$loaded_image" ]]; then
    # Add project name prefix if specified
    if [[ -n "$PROJECT_NAME" ]]; then
      new_tag="${PROJECT_NAME}_${name}:offline"
    else
      new_tag="${name}:offline"
    fi
    
    echo "  Tagging: $loaded_image → $new_tag"
    docker tag "$loaded_image" "$new_tag"
  else
    echo "  ⚠️  Warning: Could not determine loaded image for $tar"
  fi
done

echo "📌 Restoring mounted directories to $RESTORE_PATH"
mkdir -p "$RESTORE_PATH"
cp -r volumes/* "$RESTORE_PATH/"
echo "  Restored $(ls volumes/ | wc -l) volume backups"

echo "📝 Patching $COMPOSE_FILE → ${COMPOSE_FILE%.*}.patched.yml"
"$SCRIPT_DIR/scripts/patch_compose.sh" "project/$COMPOSE_FILE" "$RESTORE_PATH" "$PROJECT_NAME"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "🔍 Dry-run complete! Files prepared:"
  echo "  - Images imported with :offline tag"
  echo "  - Volumes restored to: $RESTORE_PATH"
  echo "  - Patched compose: project/${COMPOSE_FILE%.*}.patched.yml"
  echo ""
  echo "To start services, run:"
  echo "  cd project && docker compose -f ${COMPOSE_FILE%.*}.patched.yml up -d"
  echo ""
  echo "To verify setup without conflicts, use different ports in compose file"
  exit 0
fi

echo "🚀 Starting services"
cd project
docker compose -f "${COMPOSE_FILE%.*}.patched.yml" up -d

echo "✅ Import completed successfully!"
echo "  - Original file backed up as: ${COMPOSE_FILE}.bak"
echo "  - Services started with: ${COMPOSE_FILE%.*}.patched.yml"
