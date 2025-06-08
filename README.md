
📘 README.md
markdown
Copy
Edit
# Docker Offline Migrator

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

Export:

```bash
docker-migrator export -f docker-compose.yml [-f override.yml ...]
```

Import:

```bash
cd offline_bundle
docker-migrator import
```