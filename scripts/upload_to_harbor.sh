#!/bin/bash
set -e

# Script to convert exported containers to images and upload to Harbor registry
# Usage: ./upload_to_harbor.sh <bundle_path> <harbor_registry> [options]

function usage {
    echo "Docker Container to Harbor Upload Script"
    echo ""
    echo "Usage: $0 <bundle_path> <harbor_registry> [options]"
    echo ""
    echo "Arguments:"
    echo "  bundle_path      Path to the exported offline bundle"
    echo "  harbor_registry  Harbor registry URL"
    echo ""
    echo "Options:"
    echo "  --tag-suffix <suffix>    Add suffix to image tags (default: offline)"
    echo "  --dry-run                Show what would be done without executing"
    echo "  --skip-login             Skip docker login (assume already logged in)"
    echo "  --project <name>         Project name for tagging (auto-detect from compose)"
    echo "  -h, --help               Show this help message"
    exit 1
}

# Parse arguments
BUNDLE_PATH=""
HARBOR_REGISTRY=""
TAG_SUFFIX="offline"
DRY_RUN=false
SKIP_LOGIN=false
PROJECT_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tag-suffix)
            TAG_SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-login)
            SKIP_LOGIN=true
            shift
            ;;
        --project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [[ -z "$BUNDLE_PATH" ]]; then
                BUNDLE_PATH="$1"
            elif [[ -z "$HARBOR_REGISTRY" ]]; then
                HARBOR_REGISTRY="$1"
            else
                echo "Error: Too many arguments"
                usage
            fi
            shift
            ;;
    esac
done

if [[ -z "$BUNDLE_PATH" || -z "$HARBOR_REGISTRY" ]]; then
    echo "Error: Missing required arguments"
    usage
fi

# Validate bundle
if [[ ! -d "$BUNDLE_PATH" ]]; then
    echo "❌ Error: Bundle path not found: $BUNDLE_PATH"
    exit 1
fi

if [[ ! -d "$BUNDLE_PATH/containers" ]]; then
    echo "❌ Error: No containers directory found in: $BUNDLE_PATH"
    exit 1
fi

# Auto-detect project name from compose file if not provided
if [[ -z "$PROJECT_NAME" ]]; then
    if [[ -f "$BUNDLE_PATH/project/docker-compose.yaml" ]]; then
        compose_file="$BUNDLE_PATH/project/docker-compose.yaml"
    elif [[ -f "$BUNDLE_PATH/project/docker-compose.yml" ]]; then
        compose_file="$BUNDLE_PATH/project/docker-compose.yml"
    else
        echo "⚠️  Warning: No compose file found, using 'dify' as project name"
        PROJECT_NAME="dify"
    fi
    
    if [[ -n "$compose_file" ]]; then
        # Try to extract project name from compose file or directory
        PROJECT_NAME=$(grep -E "name:|project_name:" "$compose_file" 2>/dev/null | head -n1 | cut -d: -f2 | tr -d ' "' || echo "dify")
        [[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="dify"
    fi
fi

echo "🚀 Docker Container to Harbor Upload"
echo "📦 Bundle: $BUNDLE_PATH"
echo "🏗️  Registry: $HARBOR_REGISTRY"
echo "🏷️  Tag Suffix: $TAG_SUFFIX"
echo "📋 Project: $PROJECT_NAME"
echo "🔧 Mode: $([ "$DRY_RUN" = true ] && echo "DRY RUN" || echo "UPLOAD")"
echo ""

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

# Step 1: Docker login
if [[ "$SKIP_LOGIN" != true ]]; then
    echo "🔐 Step 1: Docker login to Harbor"
    harbor_host=$(echo "$HARBOR_REGISTRY" | cut -d'/' -f1)
    if [[ "$DRY_RUN" = false ]]; then
        echo "Please login to Harbor registry: $harbor_host"
        docker login "$harbor_host"
    else
        echo "   Would login to: $harbor_host"
    fi
else
    echo "⏭️  Skipping Docker login (--skip-login)"
fi

# Step 2: Load containers as images
echo ""
echo "📦 Step 2: Loading containers as images..."
container_count=$(ls "$BUNDLE_PATH/containers"/*.tar 2>/dev/null | wc -l)
echo "   Found $container_count container files"

loaded_images=()

for tar_file in "$BUNDLE_PATH/containers"/*.tar; do
    [[ -f "$tar_file" ]] || continue
    
    container_name=$(basename "$tar_file" .tar)
    echo ""
    echo "   Processing: $container_name"
    
    # Load the container as image
    if [[ "$DRY_RUN" = false ]]; then
        echo "     Loading image..."
        # Capture the actual loaded image name
        loaded_output=$(docker load -i "$tar_file" 2>&1)
        loaded_image=$(echo "$loaded_output" | grep "Loaded image:" | cut -d' ' -f3)
        
        if [[ -n "$loaded_image" ]]; then
            loaded_images+=("$loaded_image")
            echo "     Loaded: $loaded_image"
        else
            echo "     ⚠️  Warning: Could not determine loaded image name from: $loaded_output"
            # Try to find recently loaded image
            possible_image=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "${container_name%%-[0-9]+}" | head -n1)
            if [[ -n "$possible_image" ]]; then
                loaded_images+=("$possible_image")
                echo "     Found: $possible_image"
            fi
        fi
    else
        echo "     Would load: $tar_file"
        # For dry run, simulate the expected image name based on container name
        service_name=$(echo "$container_name" | sed -E 's/.*-([^-]+)-[0-9]+$/\1/')
        loaded_images+=("${PROJECT_NAME}-${service_name}:latest")
    fi
done

# Step 3: Tag and push images to Harbor
echo ""
echo "🏷️  Step 3: Tagging and pushing images to Harbor..."

for image in "${loaded_images[@]}"; do
    [[ -n "$image" ]] || continue
    
    # Extract service name from actual image name
    # Handle different image name formats
    if [[ "$image" =~ ^([^/]+)/([^:]+):(.+)$ ]]; then
        # Format: namespace/image:tag (e.g., langgenius/dify-web:1.4.0)
        namespace="${BASH_REMATCH[1]}"
        image_name="${BASH_REMATCH[2]}"
        tag="${BASH_REMATCH[3]}"
        
        # Extract service name from image name
        if [[ "$image_name" =~ dify-(.+)$ ]]; then
            service_name="${BASH_REMATCH[1]}"
        else
            service_name="$image_name"
        fi
    elif [[ "$image" =~ ^([^:]+):(.+)$ ]]; then
        # Format: image:tag (e.g., postgres:15-alpine, nginx:latest)
        image_name="${BASH_REMATCH[1]}"
        tag="${BASH_REMATCH[2]}"
        
        # Map common official images to service names
        case "$image_name" in
            postgres)
                service_name="db"
                ;;
            redis)
                service_name="redis"
                ;;
            nginx)
                service_name="nginx"
                ;;
            *)
                # For custom images like dify-ai-lhr-dev-api
                if [[ "$image_name" =~ -([^-]+)$ ]]; then
                    service_name="${BASH_REMATCH[1]}"
                else
                    service_name="$image_name"
                fi
                ;;
        esac
    else
        # Fallback for other formats
        service_name=$(echo "$image" | sed -E 's/.*[_-]([^_-]+):.*$/\1/')
    fi
    
    # Clean up service name (remove any remaining separators)
    service_name=$(echo "$service_name" | sed 's/[_-]$//')
    
    # Create Harbor image name
    harbor_image="$HARBOR_REGISTRY/${service_name}:${TAG_SUFFIX}"
    
    echo ""
    echo "   📋 Service: $service_name"
    echo "   🏷️  Source: $image"
    echo "   🎯 Target: $harbor_image"
    
    # Tag for Harbor
    execute_cmd "docker tag '$image' '$harbor_image'" "Tagging image"
    
    # Push to Harbor
    execute_cmd "docker push '$harbor_image'" "Pushing to Harbor"
done

# Step 4: Generate new compose file with Harbor images
echo ""
echo "📝 Step 4: Generating Harbor compose file..."

if [[ -f "$BUNDLE_PATH/project/docker-compose.yaml" ]]; then
    compose_file="$BUNDLE_PATH/project/docker-compose.yaml"
elif [[ -f "$BUNDLE_PATH/project/docker-compose.yml" ]]; then
    compose_file="$BUNDLE_PATH/project/docker-compose.yml"
else
    echo "⚠️  Warning: No compose file found, skipping compose file generation"
    compose_file=""
fi

if [[ -n "$compose_file" ]]; then
    harbor_compose="$BUNDLE_PATH/project/docker-compose.harbor.yml"
    
    if [[ "$DRY_RUN" = false ]]; then
        cp "$compose_file" "$harbor_compose"
        
        # Replace image references with Harbor registry
        sed -i "s|image: langgenius/dify-api:.*|image: $HARBOR_REGISTRY/api:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: langgenius/dify-web:.*|image: $HARBOR_REGISTRY/web:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: postgres:.*|image: $HARBOR_REGISTRY/db:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: redis:.*|image: $HARBOR_REGISTRY/redis:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: nginx:.*|image: $HARBOR_REGISTRY/nginx:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: semitechnologies/weaviate:.*|image: $HARBOR_REGISTRY/weaviate:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: langgenius/dify-sandbox:.*|image: $HARBOR_REGISTRY/sandbox:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: ubuntu/squid:.*|image: $HARBOR_REGISTRY/ssrf_proxy:$TAG_SUFFIX|g" "$harbor_compose"
        sed -i "s|image: langgenius/dify-plugin-daemon:.*|image: $HARBOR_REGISTRY/plugin_daemon:$TAG_SUFFIX|g" "$harbor_compose"
        
        # Replace build configurations with Harbor images for API and Worker services
        # Find and replace the build sections with image references
        
        # For API service
        sed -i '/api:/,/^  [a-zA-Z]/ {
            /# image:/c\    image: '"$HARBOR_REGISTRY"'/api:'"$TAG_SUFFIX"'
            /build:/,/dockerfile:/ {
                /build:/d
                /context:/d
                /dockerfile:/d
            }
        }' "$harbor_compose"
        
        # For Worker service
        sed -i '/worker:/,/^  [a-zA-Z]/ {
            /# image:/c\    image: '"$HARBOR_REGISTRY"'/worker:'"$TAG_SUFFIX"'
            /build:/,/dockerfile:/ {
                /build:/d
                /context:/d
                /dockerfile:/d
            }
        }' "$harbor_compose"
        
        echo "   Created: $harbor_compose"
        echo "   📋 Updated image references to Harbor registry"
    else
        echo "   Would create: $harbor_compose"
        echo "   Would update image references to Harbor registry"
    fi
fi

echo ""
if [[ "$DRY_RUN" = true ]]; then
    echo "🔍 Dry run completed! No changes were made."
    echo ""
    echo "To actually upload, run:"
    echo "   $0 $BUNDLE_PATH $HARBOR_REGISTRY"
else
    echo "✅ Upload completed successfully!"
    echo ""
    echo "🎯 Images uploaded to: $HARBOR_REGISTRY"
    echo "📋 Total images: ${#loaded_images[@]}"
    
    if [[ -n "$compose_file" ]]; then
        echo "📝 Harbor compose file: $BUNDLE_PATH/project/docker-compose.harbor.yml"
        echo ""
        echo "🚀 To deploy using Harbor images:"
        echo "   cd $BUNDLE_PATH/project"
        echo "   docker compose -f docker-compose.harbor.yml up -d"
    fi
    
    echo ""
    echo "🏷️  Uploaded images:"
    for image in "${loaded_images[@]}"; do
        [[ -n "$image" ]] || continue
        
        # Extract service name using the same logic as before
        if [[ "$image" =~ ^([^/]+)/([^:]+):(.+)$ ]]; then
            # Format: namespace/image:tag
            namespace="${BASH_REMATCH[1]}"
            image_name="${BASH_REMATCH[2]}"
            tag="${BASH_REMATCH[3]}"
            
            if [[ "$image_name" =~ dify-(.+)$ ]]; then
                service_name="${BASH_REMATCH[1]}"
            else
                service_name="$image_name"
            fi
        elif [[ "$image" =~ ^([^:]+):(.+)$ ]]; then
            # Format: image:tag
            image_name="${BASH_REMATCH[1]}"
            tag="${BASH_REMATCH[2]}"
            
            case "$image_name" in
                postgres)
                    service_name="db"
                    ;;
                redis)
                    service_name="redis"
                    ;;
                nginx)
                    service_name="nginx"
                    ;;
                *)
                    if [[ "$image_name" =~ -([^-]+)$ ]]; then
                        service_name="${BASH_REMATCH[1]}"
                    else
                        service_name="$image_name"
                    fi
                    ;;
            esac
        else
            service_name=$(echo "$image" | sed -E 's/.*[_-]([^_-]+):.*$/\1/')
        fi
        
        service_name=$(echo "$service_name" | sed 's/[_-]$//')
        echo "   - $HARBOR_REGISTRY/${service_name}:${TAG_SUFFIX}"
    done
fi 