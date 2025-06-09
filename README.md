📘 README.md
markdown
Copy
Edit
# Docker Offline Migrator

A tool for exporting and importing Docker Compose projects for offline deployment and migration.

## Features

- **export_offline**: Export running container snapshots + mounted data + compose project
- **import_offline**: Automatically patch settings + offline recovery and startup

## Installation

```bash
cd docker-offline-migrator
chmod +x *.sh scripts/*.sh
./setup.sh install         # Install as system command docker-migrator
```

## Usage Guide

### Export Command

Export a running Docker Compose project to an offline bundle for deployment in environments without internet access.

#### Syntax
```bash
docker-migrator export -f <compose.yml> [-f <...>] [-o <output_dir>]
```

#### Options
- `-f <compose.yml>`: Specify Docker Compose file (can be used multiple times)
- `-o <output_dir>`: Specify output directory (optional, default: `./offline_bundle_<timestamp>`)

#### Examples

**Basic export with default output directory:**
```bash
docker-migrator export -f docker-compose.yml
# Creates: ./offline_bundle_1703123456/
```

**Export with custom output directory:**
```bash
docker-migrator export -f docker-compose.yml -o my_backup
# Creates: ./my_backup/
```

**Export with absolute path:**
```bash
docker-migrator export -f docker-compose.yml -o /tmp/docker_backup
# Creates: /tmp/docker_backup/
```

**Export multiple compose files:**
```bash
docker-migrator export -f docker-compose.yml -f docker-compose.prod.yml -o production_backup
# Creates: ./production_backup/
```

**Export with timestamped directory:**
```bash
docker-migrator export -f docker-compose.yml -o backup_$(date +%Y%m%d_%H%M%S)
# Creates: ./backup_20231201_143022/
```

#### What Gets Exported

The export process creates a complete offline bundle containing:

1. **Container Snapshots** (`containers/`): 
   - Exports all running containers as `.tar` files
   - Preserves the current state of each container

2. **Volume Data** (`volumes/`):
   - Copies all bind mounts and named volumes
   - Maintains directory structure and permissions

3. **Project Files** (`project/`):
   - Complete project source code
   - Docker Compose files and configurations
   - Excludes previous export bundles

#### Prerequisites

- Docker and Docker Compose must be running
- Specified compose services must be started
- Sufficient disk space for export data
- `jq` tool installed for JSON parsing

### Import Command

Import and restore a previously exported offline bundle with flexible options.

#### Syntax
```bash
docker-migrator import [options]
```

#### Options
- `-f <compose.yml>`: Specify compose file in project/ (default: docker-compose.yml)
- `-r <restore_path>`: Specify restore path for volumes (default: /offline_volumes)
- `-p <project_name>`: Specify project name prefix for containers (default: auto-detect)
- `--dry-run`: Only import images and prepare files, don't start services
- `--verify`: Verify bundle structure and show what would be imported
- `-h, --help`: Show help message

#### Examples

**Verify the bundle before importing:**
```bash
cd offline_bundle
docker-migrator import --verify
```

**Dry-run import (safe testing):**
```bash
cd offline_bundle
docker-migrator import --dry-run
```

**Import with custom compose file:**
```bash
cd offline_bundle
docker-migrator import -f docker-compose.yaml
```

**Import to custom volume path:**
```bash
cd offline_bundle
docker-migrator import -r /custom/volumes/path
```

**Import with custom project name (avoid conflicts):**
```bash
cd offline_bundle
docker-migrator import -p test_env --dry-run
```

**Full import with custom settings:**
```bash
cd offline_bundle
docker-migrator import -f docker-compose.yaml -r /data/restored_volumes -p production
```

#### Import Process

The import process:

1. **🔧 Image Import**: Converts container snapshots to Docker images with `:offline` tag
2. **📌 Volume Restore**: Copies volume data to specified restore path
3. **📝 Compose Patching**: Creates patched compose file with offline image references
4. **🚀 Service Startup**: Starts services using patched configuration (unless dry-run)

#### Safe Testing Workflow

For testing without conflicts with existing services:

```bash
# 1. Verify the bundle
cd /data/export-dify-offline
docker-migrator import --verify

# 2. Dry-run to prepare files
docker-migrator import --dry-run -r /tmp/test_volumes -p test

# 3. Manually edit ports in patched compose file to avoid conflicts
nano project/docker-compose.patched.yml

# 4. Start services manually for testing
cd project
docker compose -f docker-compose.patched.yml up -d

# 5. When satisfied, clean up test environment
docker compose -f docker-compose.patched.yml down
docker system prune -f
```

## Directory Structure

After export, the offline bundle contains:
```
offline_bundle_<timestamp>/
├── containers/          # Container snapshots (.tar files)
├── volumes/            # Volume and bind mount backups
└── project/            # Project source code and configs
```

## Use Cases

- **Offline Deployment**: Deploy applications in air-gapped environments
- **Environment Migration**: Move applications between different hosts
- **Backup & Recovery**: Create complete application snapshots
- **Development**: Share complete development environments

## Complete Offline Deployment Workflow

For users who want to deploy an exact copy of their Docker Compose project on a new machine without internet access.

### Quick Start

**On the source machine:**
```bash
# 1. Export your running project
docker-migrator export -f /path/to/docker-compose.yaml -o /data/my-project-offline

# 2. Transfer the bundle to target machine
# (via USB, network copy, etc.)
```

**On the target machine:**
```bash
# 3. Deploy with one command
docker-migrator deploy /data/my-project-offline /opt/my-project

# 4. Start services
cd /opt/my-project
docker compose up -d
```

### Deploy Command

Deploy an exported offline bundle to a new location with automatic setup.

#### Syntax
```bash
docker-migrator deploy <bundle_path> <target_project_path> [options]
```

#### Options
- `--dry-run`: Show what would be done without executing
- `--backup`: Create backup of existing project
- `--force`: Overwrite existing project without asking
- `-h, --help`: Show help message

#### Examples

**Basic deployment:**
```bash
docker-migrator deploy /data/export-dify-offline /opt/dify
```

**Safe deployment with backup:**
```bash
docker-migrator deploy /data/export-dify-offline /home/user/dify --backup
```

**Preview deployment without changes:**
```bash
docker-migrator deploy /data/export-dify-offline /opt/dify --dry-run
```

#### What the Deploy Command Does

1. **🔧 Loads Docker Images**: Imports all exported images and creates simple `:offline` tags
2. **📁 Deploys Project Files**: Copies the complete project structure to target location
3. **💾 Restores Volume Data**: Maps and restores all volume data to correct locations
4. **📝 Updates Compose File**: Automatically replaces image tags with offline versions
5. **✅ Ready to Start**: Project is immediately ready for `docker compose up -d`

#### Target Directory Structure

After deployment, your target directory will contain:
```
/opt/my-project/
├── docker-compose.yaml          # Updated with :offline tags
├── docker-compose.yaml.original # Backup of original
├── volumes/                     # All volume data restored
│   ├── app/storage/
│   ├── db/data/
│   └── redis/data/
├── nginx/                       # All project files
├── scripts/
└── ...
```

### Alternative: Manual Deployment

If you prefer more control over the deployment process:

**Step 1: Load images and create simple tags**
```bash
cd /path/to/bundle
docker-migrator import --dry-run -p myproject
/path/to/scripts/create_simple_tags.sh myproject project/docker-compose.yaml
```

**Step 2: Copy project and update compose file**
```bash
cp -r project/ /opt/my-project/
cd /opt/my-project
cp docker-compose.yaml docker-compose.yaml.original
sed -i 's/:1\.4\.0/:offline/g; s/:15-alpine/:offline/g; s/:latest/:offline/g' docker-compose.yaml
```

**Step 3: Restore volume data**
```bash
mkdir -p volumes/
# Copy volume data from bundle/volumes/ to volumes/ with proper mapping
```

**Step 4: Start services**
```bash
docker compose up -d
```