#!/usr/bin/env bash
# Loads and starts the Logos modules once the daemon answers.
# Installed to /usr/local/bin and run by logos-bootstrap.service.
export HOME=/var/lib/logos-node LOGOSCTL_CONFIG_DIR=/var/lib/logos-node/.logosctl
cd /var/lib/logos-node
for _ in $(seq 1 60); do logosctl daemon status >/dev/null 2>&1 && break; sleep 5; done
logosctl daemon status >/dev/null 2>&1 || { echo "daemon not up"; exit 1; }
run() { echo "+ $*"; "$@" 2>&1 | tail -c 600; echo; }
run logosctl module load blockchain_module
run logosctl call blockchain_module start /var/lib/logos-node/user_config.yaml ""
cd /var/lib/logos-node/storage-module
run logosctl module load storage_module
run logosctl call storage_module init @config.json
run logosctl call storage_module start
cd /var/lib/logos-node/delivery-module
run logosctl module load delivery_module
run logosctl call delivery_module createNode @config.json
run logosctl call delivery_module start
logosctl module ls --loaded
