#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

in="$1"; root="$2"; project_prefix="$3"
out="${in%.*}.patched.yml"

echo "🔧 Patching compose file: $in → $out"
echo "📁 Volume root: $root"
echo "🏷️  Project prefix: $project_prefix"

# Backup original file
cp "$in" "${in}.bak"

# Get list of available offline images
available_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep ":offline$" | sort)
echo "🔍 Available offline images:"
echo "$available_images" | sed 's/^/  - /'

# Create patched file
current_service=""
{
  while IFS= read -r l; do
    # Track current service name
    if [[ "$l" =~ ^[[:space:]]*([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
      current_service="${BASH_REMATCH[1]}"
      echo "$l"
    elif [[ "$l" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
      # Replace image references with :offline tagged versions
      original_image="${BASH_REMATCH[1]}"
      
      # Try to find matching offline image based on service name
      matching_image=""
      
      # Strategy 1: Look for service-based container name
      if [[ -n "$current_service" && -n "$project_prefix" ]]; then
        # Try: project_prefix_original-project-name-service-1:offline
        service_pattern="${project_prefix}_.*${current_service}.*:offline"
        while IFS= read -r img; do
          if [[ "$img" =~ $service_pattern ]]; then
            matching_image="$img"
            break
          fi
        done <<< "$available_images"
      fi
      
      # Strategy 2: Look for service name in image name
      if [[ -z "$matching_image" && -n "$current_service" ]]; then
        while IFS= read -r img; do
          if [[ "$img" =~ .*${current_service}.*:offline$ ]]; then
            matching_image="$img"
            break
          fi
        done <<< "$available_images"
      fi
      
      # Strategy 3: Try original image name pattern
      if [[ -z "$matching_image" ]]; then
        sanitized_name=$(sanitize "$original_image")
        candidate="${sanitized_name}:offline"
        if [[ -n "$project_prefix" ]]; then
          candidate="${project_prefix}_${sanitized_name}:offline"
        fi
        
        while IFS= read -r img; do
          if [[ "$img" == "$candidate" ]]; then
            matching_image="$img"
            break
          fi
        done <<< "$available_images"
      fi
      
      # Strategy 4: Try to find by base name
      if [[ -z "$matching_image" ]]; then
        base_name=$(echo "$original_image" | cut -d':' -f1 | tr '/' '_' | tr '-' '_')
        while IFS= read -r img; do
          if [[ "$img" =~ $base_name.*:offline$ ]]; then
            matching_image="$img"
            break
          fi
        done <<< "$available_images"
      fi
      
      if [[ -n "$matching_image" ]]; then
        echo "    image: $matching_image"
        echo "🔄 Patched image: $original_image → $matching_image (service: $current_service)" >&2
      else
        echo "    image: $original_image"
        echo "⚠️  Warning: No offline image found for: $original_image (service: $current_service)" >&2
      fi
    elif [[ "$l" =~ ^[[:space:]]*-[[:space:]]+([^:]+):(/.*) ]]; then
      # Replace volume mounts with restored paths (only lines starting with - and containing filesystem paths)
      vol_src="${BASH_REMATCH[1]}"
      vol_dst="${BASH_REMATCH[2]}"
      vol=$(basename "$vol_src")
      tgt="${root}/${vol}:${vol_dst}"
      echo "      - $tgt"
      echo "🔄 Patched volume: $vol_src:$vol_dst → $tgt" >&2
    else
      echo "$l"
    fi
  done < "$in"
} > "$out"

echo "✅ Patch completed: $out"
