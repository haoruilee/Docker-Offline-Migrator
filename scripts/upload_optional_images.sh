#!/bin/bash
set -e

# Script to pull and upload optional Dify images to Harbor
# Usage: ./upload_optional_images.sh <harbor_registry> [options]

function usage {
    echo "Upload Optional Dify Images to Harbor Script"
    echo ""
    echo "Usage: $0 <harbor_registry> [options]"
    echo ""
    echo "Arguments:"
    echo "  harbor_registry  Harbor registry URL"
    echo ""
    echo "Options:"
    echo "  --tag-suffix <suffix>    Add suffix to image tags (default: v1)"
    echo "  --dry-run                Show what would be done without executing"
    echo "  --skip-login             Skip docker login (assume already logged in)"
    echo "  --help                   Show this help message"
    echo ""
    echo "Optional Images:"
    echo "  - Milvus (etcd, minio, milvus-standalone)"
    echo "  - Qdrant"
    echo "  - Chroma"
    echo "  - PGVector"
    echo "  - OpenSearch + Dashboards"
    echo "  - Elasticsearch + Kibana"
    echo "  - MyScale"
    echo "  - OceanBase"
    echo "  - Oracle"
    echo "  - OpenGauss"
    echo "  - Certbot"
    echo "  - Unstructured"
}

# Parse arguments
HARBOR_REGISTRY=""
TAG_SUFFIX="v1"
DRY_RUN=false
SKIP_LOGIN=false

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
        --help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$HARBOR_REGISTRY" ]]; then
                HARBOR_REGISTRY="$1"
            else
                echo "Too many arguments"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$HARBOR_REGISTRY" ]]; then
    echo "Error: Harbor registry is required"
    usage
    exit 1
fi

echo "🚀 Dify Optional Images to Harbor Upload Script"
echo "================================================"
echo "Harbor Registry: $HARBOR_REGISTRY"
echo "Tag Suffix: $TAG_SUFFIX"
echo "Dry Run: $DRY_RUN"
echo ""

# Define optional images with their service names
declare -A OPTIONAL_IMAGES=(
    # Milvus ecosystem
    ["quay.io/coreos/etcd:v3.5.5"]="etcd"
    ["minio/minio:RELEASE.2023-03-20T20-16-18Z"]="minio"
    ["milvusdb/milvus:v2.5.0-beta"]="milvus"
    
    # Vector databases
    ["langgenius/qdrant:v1.7.3"]="qdrant"
    ["ghcr.io/chroma-core/chroma:0.5.20"]="chroma"
    ["pgvector/pgvector:pg16"]="pgvector"
    ["tensorchord/pgvecto-rs:pg16-v0.3.0"]="pgvecto-rs"
    
    # Search engines
    ["opensearchproject/opensearch:latest"]="opensearch"
    ["opensearchproject/opensearch-dashboards:latest"]="opensearch-dashboards"
    ["docker.elastic.co/elasticsearch/elasticsearch:8.14.3"]="elasticsearch"
    ["docker.elastic.co/kibana/kibana:8.14.3"]="kibana"
    
    # Other databases
    ["myscale/myscaledb:1.6.4"]="myscale"
    ["oceanbase/oceanbase-ce:4.3.5.1-101000042025031818"]="oceanbase"
    ["container-registry.oracle.com/database/free:latest"]="oracle"
    ["opengauss/opengauss:7.0.0-RC1"]="opengauss"
    ["vastdata/vastbase-vector"]="vastbase"
    
    # Utilities
    ["certbot/certbot"]="certbot"
    ["downloads.unstructured.io/unstructured-io/unstructured-api:latest"]="unstructured"
)

# Step 1: Harbor login
if [[ "$SKIP_LOGIN" = false ]]; then
    echo "🔐 Step 1: Harbor login..."
    if [[ "$DRY_RUN" = false ]]; then
        harbor_host=$(echo "$HARBOR_REGISTRY" | cut -d'/' -f1)
        echo "   Logging in to $harbor_host"
        docker login "$harbor_host"
    else
        echo "   [DRY RUN] Would login to Harbor"
    fi
else
    echo "🔐 Step 1: Skipping Harbor login (--skip-login)"
fi

echo ""

# Step 2: Pull, tag and push images
echo "📦 Step 2: Processing optional images..."
echo "   Found ${#OPTIONAL_IMAGES[@]} optional images"

successful_uploads=()
failed_uploads=()

for original_image in "${!OPTIONAL_IMAGES[@]}"; do
    service_name="${OPTIONAL_IMAGES[$original_image]}"
    harbor_image="$HARBOR_REGISTRY/$service_name:$TAG_SUFFIX"
    
    echo ""
    echo "   Processing: $service_name"
    echo "     Original: $original_image"
    echo "     Harbor:   $harbor_image"
    
    if [[ "$DRY_RUN" = false ]]; then
        # Pull original image
        echo "     Pulling..."
        if docker pull "$original_image"; then
            echo "     ✅ Pull successful"
            
            # Tag for Harbor
            echo "     Tagging..."
            if docker tag "$original_image" "$harbor_image"; then
                echo "     ✅ Tag successful"
                
                # Push to Harbor
                echo "     Pushing..."
                if docker push "$harbor_image"; then
                    echo "     ✅ Push successful"
                    successful_uploads+=("$service_name")
                else
                    echo "     ❌ Push failed"
                    failed_uploads+=("$service_name")
                fi
            else
                echo "     ❌ Tag failed"
                failed_uploads+=("$service_name")
            fi
        else
            echo "     ❌ Pull failed"
            failed_uploads+=("$service_name")
        fi
    else
        echo "     [DRY RUN] Would pull, tag and push"
        successful_uploads+=("$service_name")
    fi
done

echo ""
echo "🎉 Upload Summary"
echo "================="
echo "✅ Successful uploads (${#successful_uploads[@]}):"
for service in "${successful_uploads[@]}"; do
    echo "   - $service"
done

if [[ ${#failed_uploads[@]} -gt 0 ]]; then
    echo ""
    echo "❌ Failed uploads (${#failed_uploads[@]}):"
    for service in "${failed_uploads[@]}"; do
        echo "   - $service"
    done
fi

echo ""
echo "🏷️  Harbor images uploaded:"
for service in "${successful_uploads[@]}"; do
    echo "   $HARBOR_REGISTRY/$service:$TAG_SUFFIX"
done

echo ""
echo "✨ Optional images upload completed!"
echo "   You can now use these images in your offline deployment." 