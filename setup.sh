#!/bin/bash
install -m 755 export_offline.sh /usr/local/bin/docker-migrator-export
install -m 755 import_offline.sh /usr/local/bin/docker-migrator-import
echo "Installed docker-migrator-export/import"