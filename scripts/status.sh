#!/usr/bin/env bash
# One-screen health check for the Logos node.
L() { runuser -u logos -- env HOME=/var/lib/logos-node LOGOSCTL_CONFIG_DIR=/var/lib/logos-node/.logosctl bash -c "cd /var/lib/logos-node && $*"; }
echo "services:  node=$(systemctl is-active logos-node)  blend-timer=$(systemctl is-active logos-blend-join.timer)"
printf 'chain:     '; L "logosctl call blockchain_module get_cryptarchia_info" | jq -r .result.value | jq -c '{mode,height,slot}'
printf 'modules:   '; L "logosctl module ls --loaded" | jq -r '[.[].name] | join(", ")'
printf 'blend:     '
if [ -f /var/lib/logos-node/.blend-joined ]; then echo "joined"; else echo "not yet (the timer retries every 20 min)"; fi
echo "listeners:"
ss -lntup | grep -E ':(3000|8090|8091|9000|30303|8080) ' | awk '{print "  " $1 " " $5}'
