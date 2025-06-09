#!/bin/bash

# Create simple offline tags for easier compose file modification
echo "🏷️  Creating simple offline tags..."

project_prefix="$1"
compose_file="$2"

if [[ -z "$project_prefix" || -z "$compose_file" ]]; then
    echo "Usage: $0 <project_prefix> <compose_file>"
    echo "Example: $0 dify_test project/docker-compose.yaml"
    exit 1
fi

if [[ ! -f "$compose_file" ]]; then
    echo "Error: Compose file not found: $compose_file"
    exit 1
fi

echo "📋 Project prefix: $project_prefix"
echo "📄 Compose file: $compose_file"

# Get list of available offline images
available_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${project_prefix}_.*:offline$")

if [[ -z "$available_images" ]]; then
    echo "❌ No offline images found with prefix: $project_prefix"
    exit 1
fi

echo "🔍 Found offline images:"
echo "$available_images" | sed 's/^/  - /'

# Extract service definitions and their images from compose file
echo ""
echo "🔄 Creating simple tags..."

declare -A created_tags

while IFS= read -r offline_image; do
    # Extract container name from offline image name
    # Format: project_prefix_container-name:offline
    container_name=$(echo "$offline_image" | sed "s/^${project_prefix}_//; s/:offline$//")
    
    # Try to find the service name by matching container name pattern
    # Container names usually follow: project-service-1 format
    service_name=$(echo "$container_name" | sed 's/.*-\([^-]*\)-[0-9]*$/\1/')
    
    echo "🔍 Processing: $offline_image"
    echo "   Container: $container_name"
    echo "   Service: $service_name"
    
    # Find the original image for this service in compose file
    original_image=""
    in_service=false
    current_service=""
    
    while IFS= read -r line; do
        # Check if we're entering a service definition
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            current_service="${BASH_REMATCH[1]}"
            if [[ "$current_service" == "$service_name" ]]; then
                in_service=true
            else
                in_service=false
            fi
        elif [[ "$in_service" == true && "$line" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
            original_image="${BASH_REMATCH[1]}"
            break
        fi
    done < "$compose_file"
    
    if [[ -n "$original_image" ]]; then
        # Create simple tag: original_image_name:offline
        simple_tag="${original_image%:*}:offline"
        
        # Avoid duplicate tags
        if [[ -z "${created_tags[$simple_tag]}" ]]; then
            echo "   ✅ Tagging: $offline_image → $simple_tag"
            docker tag "$offline_image" "$simple_tag"
            created_tags["$simple_tag"]=1
        else
            echo "   ⚠️  Tag already exists: $simple_tag"
        fi
    else
        echo "   ⚠️  Could not find original image for service: $service_name"
    fi
    echo ""
done <<< "$available_images"

echo "✅ Simple tags created!"
echo ""
echo "📝 Now you can modify your compose file by replacing version tags with :offline"
echo ""
echo "💡 Suggested sed command:"
echo "   cp $compose_file ${compose_file}.backup"
echo "   sed -i 's/:1\.4\.0/:offline/g; s/:15-alpine/:offline/g; s/:6-alpine/:offline/g; s/:latest/:offline/g; s/:0\.2\.12/:offline/g; s/:0\.0\.10-local/:offline/g; s/:1\.19\.0/:offline/g' $compose_file"
echo ""
echo "🔍 Or check what tags were created:"
echo "   docker images | grep ':offline'" 