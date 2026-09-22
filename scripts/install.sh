#!/usr/bin/env bash
# Logos testnet node (release set v0.2.1): logosctl + blockchain/storage/delivery
# modules, systemd autostart, firewall, faucet, and an automatic Blend join.
# Usage: sudo bash install.sh [public-ip]
#
# Versions and hashes below are the ones pinned by the official Node Operator
# Guide for v0.2.1. When Logos ships a new release set, update them from
# https://roadmap.logos.co/testnets/logos-node-operator-guide
set -euo pipefail

LOGOSCTL_VER=0.2.3-rc.1
LOGOSCTL_TGZ_SHA=baa6e24522833c6b6e33146a9d44f7428660e465158be2d723575f62409ad851
LOGOSCTL_APPIMAGE_SHA=3ee96869d6a873cddd19c05eaa86d258e156a69635b10811b77cda149899dd1e
BLOCKCHAIN_VER=0.2.4; BLOCKCHAIN_HASH=2e57268c4ec1fdcf07e4b6bf1b33b5ac99705c071f879e6ca1c41b4e543cc674
STORAGE_VER=2.1.2;    STORAGE_HASH=19b11b153748c30665608c5527776ba2be74f7764481a11d33f687098764b740
DELIVERY_VER=0.2.1;   DELIVERY_HASH=0bccd85b4702c01a2c227df8aa55b3f5159a9fe009d57ae8bb8b3a7c20dfcbbe

[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
HOME_DIR=/var/lib/logos-node

apt-get update -qq
apt-get install -y -qq curl jq tar fuse3 >/dev/null
IP=${1:-$(curl -fsS -4 https://api.ipify.org)}
echo "public IP: $IP"

# 1) logosctl, checksum-verified
if [ ! -x /usr/local/bin/logosctl ]; then
  cd /tmp
  curl -fsSL -o logosctl.tgz "https://github.com/logos-co/logos-logoscore-cli/releases/download/${LOGOSCTL_VER}/logosctl-x86_64-linux.tar.gz"
  echo "${LOGOSCTL_TGZ_SHA}  logosctl.tgz" | sha256sum --check
  tar -xzf logosctl.tgz
  echo "${LOGOSCTL_APPIMAGE_SHA}  logosctl-x86_64.AppImage" | sha256sum --check
  install -m755 logosctl-x86_64.AppImage /usr/local/bin/logosctl
fi
logosctl --version | head -1

# 2) Dedicated system user and directories
id logos >/dev/null 2>&1 || useradd --system --home "$HOME_DIR" --create-home --shell /usr/sbin/nologin logos
mkdir -p "$HOME_DIR"/{.logosctl,blockchain-module-testnet,storage-module/storage-data,delivery-module}
chmod 700 "$HOME_DIR/.logosctl"
L() { runuser -u logos -- env HOME="$HOME_DIR" LOGOSCTL_CONFIG_DIR="$HOME_DIR/.logosctl" bash -c "cd $HOME_DIR && $*"; }

# 3) Module configs (templates in ../config)
cp "$HERE/../config/peers.json" "$HOME_DIR/blockchain-module-testnet/peers.json"
cp "$HERE/../config/storage.json" "$HOME_DIR/storage-module/config.json"
sed "s|__PUBLIC_IP__|${IP}|" "$HERE/../config/delivery.json" > "$HOME_DIR/delivery-module/config.json"
echo "$IP" > "$HOME_DIR/.public-ip"
chown -R logos:logos "$HOME_DIR"

# 4) Install the pinned modules and let the node generate its own keys/config
L "printf '{}\n' | logosctl daemon config set -" >/dev/null
L "logosctl daemon start --detach" >/dev/null
L "logosctl catalog refresh" >/dev/null
L "logosctl package install blockchain_module --version $BLOCKCHAIN_VER --root-hash $BLOCKCHAIN_HASH --yes" >/dev/null
L "logosctl package install storage_module --version $STORAGE_VER --root-hash $STORAGE_HASH --yes" >/dev/null
L "logosctl package install delivery_module --version $DELIVERY_VER --root-hash $DELIVERY_HASH --yes" >/dev/null
L "logosctl package ls --type core" | jq -r '.[] | "  \(.name) \(.version)"'
if [ ! -f "$HOME_DIR/user_config.yaml" ]; then
  L "logosctl module load blockchain_module" >/dev/null
  L "cd blockchain-module-testnet && logosctl call blockchain_module generate_user_config @peers.json" >/dev/null
fi
chmod 600 "$HOME_DIR/user_config.yaml" "$HOME_DIR/keystore.yaml"
L "logosctl daemon stop" >/dev/null || true
BLEND_PORT=$(grep -oP 'listening_address: /ip4/0\.0\.0\.0/udp/\K[0-9]+' "$HOME_DIR/user_config.yaml" | head -1)
echo "blend port: $BLEND_PORT/udp"

# 5) systemd: daemon + module bootstrap + Blend auto-join timer
install -m755 "$HERE/logos-bootstrap.sh" /usr/local/bin/logos-bootstrap.sh
install -m755 "$HERE/logos-blend-join.sh" /usr/local/bin/logos-blend-join.sh
install -m644 "$HERE"/../systemd/*.service "$HERE"/../systemd/*.timer /etc/systemd/system/
mkdir -p /etc/systemd/journald.conf.d
install -m644 "$HERE/../systemd/journald-cap.conf" /etc/systemd/journald.conf.d/logos-cap.conf
systemctl restart systemd-journald

# 6) Firewall
if command -v ufw >/dev/null; then
  ufw allow 22/tcp >/dev/null
  for r in 3000/udp "$BLEND_PORT/udp" 8090/udp 8091/tcp 9000/udp 30303/tcp; do
    ufw allow "$r" comment logos >/dev/null
  done
  ufw --force enable >/dev/null
fi

systemctl daemon-reload
systemctl enable logos-node.service logos-bootstrap.service logos-blend-join.timer >/dev/null
systemctl start logos-node.service
systemctl start logos-bootstrap.service || true
systemctl start logos-blend-join.timer

# 7) Testnet funds for the node's own keys (consensus + Blend)
for k in LeaderFunding BlendZk SdpFunding; do
  PK=$(awk -v k="$k:" '/^public_keys:/{f=1} f && $1==k {print $2; exit}' "$HOME_DIR/keystore.yaml")
  printf 'faucet %s: ' "$k"
  curl -fsS -m 30 -X POST "https://testnet.blockchain.logos.co/web/faucet-backend/$PK" || true
  echo
  sleep 20
done

echo
echo "Done. The node syncs on its own and joins Blend automatically once funded."
echo "Status:  sudo bash $HERE/status.sh"
