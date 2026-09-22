#!/usr/bin/env bash
# Run by logos-blend-join.timer. Once the node is Online and its BlendZk and
# SdpFunding keys hold a note, it joins Blend once and records it. Until then it
# re-requests faucet funds for any key that is still empty.
set -uo pipefail
export HOME=/var/lib/logos-node LOGOSCTL_CONFIG_DIR=/var/lib/logos-node/.logosctl
cd /var/lib/logos-node
DONE=/var/lib/logos-node/.blend-joined
[ -f "$DONE" ] && exit 0

pk() { awk -v k="$1:" '/^public_keys:/{f=1} f && $1==k {print $2; exit}' keystore.yaml; }
note() {
  logosctl call blockchain_module wallet_get_notes "$1" "" \
    | jq -r .result.value | jq -r '.notes // [] | .[0].id // empty'
}

ZK=$(pk BlendZk); SDP=$(pk SdpFunding); LEAD=$(pk LeaderFunding)
MODE=$(logosctl call blockchain_module get_cryptarchia_info | jq -r .result.value | jq -r .mode)
echo "mode=$MODE"
[ "$MODE" = "Online" ] || exit 0

ZKNOTE=$(note "$ZK"); SDPNOTE=$(note "$SDP"); LEADNOTE=$(note "$LEAD")
echo "notes: blendzk=${ZKNOTE:-none} sdp=${SDPNOTE:-none} leader=${LEADNOTE:-none}"
for pair in "$ZK:$ZKNOTE" "$SDP:$SDPNOTE" "$LEAD:$LEADNOTE"; do
  k=${pair%%:*}; n=${pair#*:}
  if [ -z "$n" ]; then
    printf 'faucet %s: ' "$k"
    curl -fsS -m 30 -X POST "https://testnet.blockchain.logos.co/web/faucet-backend/$k"
    echo
  fi
done
[ -n "$ZKNOTE" ] && [ -n "$SDPNOTE" ] || exit 0

IP=$(cat /var/lib/logos-node/.public-ip)
PORT=$(grep -oP 'listening_address: /ip4/0\.0\.0\.0/udp/\K[0-9]+' user_config.yaml | head -1)
OUT=$(logosctl call blockchain_module blend_join_as_core_node "/ip4/${IP}/udp/${PORT}/quic-v1" "$ZKNOTE")
echo "$OUT"
if echo "$OUT" | jq -e '.result.success == true' >/dev/null 2>&1; then
  echo "$OUT" > "$DONE"
fi
