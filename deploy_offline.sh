#!/bin/bash
set -e

# Docker Offline Deployment Script
# This script deploys an exported offline bundle to a new machine

function usage {
    echo "Docker Offline Deployment Script"
    echo ""
    echo "Usage: $0 <bundle_path> <target_project_path> [options]"
    echo ""
    echo "Arguments:"
    echo "  bundle_path         Path to the exported offline bundle"
    echo "  target_project_path Path where the project should be deployed"
    echo ""
    echo "Options:"
    echo "  --dry-run          Show what would be done without executing"
    echo "  --backup           Create backup of existing project"
    echo "  --force            Overwrite existing project without asking"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 /data/export-dify-offline-v4 /opt/dify"
    echo "  $0 /data/export-dify-offline-v4 /home/user/dify --backup"
    exit 1
}

# Parse arguments
BUNDLE_PATH=""
TARGET_PATH=""
DRY_RUN=false
BACKUP=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --backup)
            BACKUP=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$BUNDLE_PATH" ]]; then
                BUNDLE_PATH="$1"
            elif [[ -z "$TARGET_PATH" ]]; then
                TARGET_PATH="$1"
            else
                echo "Error: Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$BUNDLE_PATH" || -z "$TARGET_PATH" ]]; then
    echo "Error: Missing required arguments"
    usage
fi

# Validate bundle
if [[ ! -d "$BUNDLE_PATH" ]]; then
    echo "❌ Error: Bundle path not found: $BUNDLE_PATH"
    exit 1
fi

if [[ ! -d "$BUNDLE_PATH/containers" || ! -d "$BUNDLE_PATH/volumes" || ! -d "$BUNDLE_PATH/project" ]]; then
    echo "❌ Error: Invalid bundle structure in: $BUNDLE_PATH"
    exit 1
fi

echo "🚀 Docker Offline Deployment"
echo "📦 Bundle: $BUNDLE_PATH"
echo "🎯 Target: $TARGET_PATH"
echo "🔧 Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "DEPLOY")"
echo ""

# Check if target exists
if [[ -d "$TARGET_PATH" ]]; then
    if [[ "$FORCE" != true ]]; then
        echo "⚠️  Target directory already exists: $TARGET_PATH"
        if [[ "$BACKUP" = true ]]; then
            echo "📋 Will create backup before deployment"
        else
            echo "❌ Use --force to overwrite or --backup to create backup"
            exit 1
        fi
    fi
fi

# Function to execute or show command
execute_cmd() {
    local cmd="$1"
    local desc="$2"
    
    echo "🔄 $desc"
    if [[ "$DRY_RUN" = true ]]; then
        echo "   Command: $cmd"
    else
        echo "   Executing: $cmd"
        eval "$cmd"
    fi
}

# Step 1: Load Docker images
echo "📦 Step 1: Loading Docker images..."
container_count=$(ls "$BUNDLE_PATH/containers"/*.tar 2>/dev/null | wc -l)
echo "   Found $container_count container images"

if [[ "$DRY_RUN" = false ]]; then
    for tar_file in "$BUNDLE_PATH/containers"/*.tar; do
        [[ -f "$tar_file" ]] || continue
        echo "   Loading: $(basename "$tar_file")"
        docker load -i "$tar_file" >/dev/null
    done
fi

# Step 2: Create simple offline tags
echo ""
echo "🏷️  Step 2: Creating simple offline tags..."
if [[ -f "$BUNDLE_PATH/project/docker-compose.yaml" ]]; then
    compose_file="$BUNDLE_PATH/project/docker-compose.yaml"
elif [[ -f "$BUNDLE_PATH/project/docker-compose.yml" ]]; then
    compose_file="$BUNDLE_PATH/project/docker-compose.yml"
else
    echo "❌ Error: No docker-compose file found in bundle"
    exit 1
fi

# Extract project name from bundle path for tagging
project_name=$(basename "$BUNDLE_PATH" | sed 's/export-//' | sed 's/-offline.*//')
if [[ "$DRY_RUN" = false ]]; then
    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$SCRIPT_DIR/scripts/create_simple_tags.sh" ]]; then
        "$SCRIPT_DIR/scripts/create_simple_tags.sh" "dify_test" "$compose_file"
    else
        echo "⚠️  Warning: create_simple_tags.sh not found, skipping tag creation"
    fi
fi

# Step 3: Backup existing project if requested
if [[ "$BACKUP" = true && -d "$TARGET_PATH" ]]; then
    backup_path="${TARGET_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
    execute_cmd "cp -r '$TARGET_PATH' '$backup_path'" "Creating backup: $backup_path"
fi

# Step 4: Deploy project files
echo ""
echo "📁 Step 3: Deploying project files..."
execute_cmd "mkdir -p '$(dirname "$TARGET_PATH")'" "Creating parent directory"
execute_cmd "cp -r '$BUNDLE_PATH/project' '$TARGET_PATH'" "Copying project files"

# Step 5: Deploy volume data
echo ""
echo "💾 Step 4: Deploying volume data..."
volume_count=$(ls -1 "$BUNDLE_PATH/volumes" 2>/dev/null | wc -l)
echo "   Found $volume_count volume backups"

execute_cmd "mkdir -p '$TARGET_PATH/volumes'" "Creating volumes directory"

if [[ "$DRY_RUN" = false ]]; then
    for volume_dir in "$BUNDLE_PATH/volumes"/*; do
        [[ -d "$volume_dir" ]] || continue
        volume_name=$(basename "$volume_dir")
        
        # Map volume names back to original structure
        case "$volume_name" in
            *_app_api_storage)
                target_vol="$TARGET_PATH/volumes/app/storage"
                ;;
            *_var_lib_postgresql_data)
                target_vol="$TARGET_PATH/volumes/db/data"
                ;;
            *_data)
                # Handle generic data volumes
                if [[ "$volume_name" =~ redis ]]; then
                    target_vol="$TARGET_PATH/volumes/redis/data"
                else
                    target_vol="$TARGET_PATH/volumes/$(echo "$volume_name" | sed 's/.*_//')"
                fi
                ;;
            *)
                # Try to extract meaningful path from volume name
                clean_name=$(echo "$volume_name" | sed 's/^[^_]*_[^_]*_[^_]*_[^_]*_//' | tr '_' '/')
                target_vol="$TARGET_PATH/volumes/$clean_name"
                ;;
        esac
        
        echo "   Deploying: $volume_name → $(basename "$target_vol")"
        mkdir -p "$(dirname "$target_vol")"
        cp -r "$volume_dir"/* "$target_vol/" 2>/dev/null || true
    done
fi

# Step 6: Update compose file with offline tags
echo ""
echo "📝 Step 5: Updating compose file with offline tags..."
target_compose="$TARGET_PATH/docker-compose.yaml"
[[ -f "$target_compose" ]] || target_compose="$TARGET_PATH/docker-compose.yml"

if [[ -f "$target_compose" ]]; then
    execute_cmd "cp '$target_compose' '${target_compose}.original'" "Backing up original compose file"
    
    # Replace image tags with offline versions
    sed_cmd="sed -i 's/:1\.4\.0/:offline/g; s/:15-alpine/:offline/g; s/:6-alpine/:offline/g; s/:latest/:offline/g; s/:0\.2\.12/:offline/g; s/:0\.0\.10-local/:offline/g; s/:1\.19\.0/:offline/g' '$target_compose'"
    execute_cmd "$sed_cmd" "Updating image tags to offline versions"
else
    echo "⚠️  Warning: No compose file found in target directory"
fi

echo ""
if [[ "$DRY_RUN" = true ]]; then
    echo "🔍 Dry run completed! No changes were made."
    echo ""
    echo "To actually deploy, run:"
    echo "   $0 $BUNDLE_PATH $TARGET_PATH"
else
    echo "✅ Deployment completed successfully!"
    echo ""
    echo "🚀 To start the services:"
    echo "   cd $TARGET_PATH"
    echo "   docker compose up -d"
    echo ""
    echo "📋 Files deployed:"
    echo "   Project: $TARGET_PATH"
    echo "   Volumes: $TARGET_PATH/volumes/"
    echo "   Compose: $target_compose"
    echo "   Backup: ${target_compose}.original"
fi 