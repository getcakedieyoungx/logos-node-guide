```
  ██╗      ██████╗  ██████╗  ██████╗ ███████╗
  ██║     ██╔═══██╗██╔════╝ ██╔═══██╗██╔════╝
  ██║     ██║   ██║██║  ███╗██║   ██║███████╗
  ██║     ██║   ██║██║   ██║██║   ██║╚════██║
  ███████╗╚██████╔╝╚██████╔╝╚██████╔╝███████║
  ╚══════╝ ╚═════╝  ╚═════╝  ╚═════╝ ╚══════╝
     N O D E   ·   T E S T N E T   v 0 . 2 . 1
```

# Logos Node Guide

One script that installs a **Logos testnet node** (blockchain + storage + delivery), runs it under systemd so it survives reboots, requests testnet funds, and **joins the Blend network by itself** once the funds arrive.

> Written from a real install on 22 Sep 2026, on the same VPS as two other nodes.

---

## What Logos is, and what you actually earn

- **The Logos stack** comes from the Institute of Free Technology (the team behind Status and Nimbus). It has three parts: **Blockchain** (formerly Nomos), **Messaging** (Waku) and **Storage** (Codex).
- Testnet v0.1 ran in March 2026 with 357 nodes. v0.2 arrived on 30 June. This guide pins **release set v0.2.1**.
- Blend is the mixnet behind the chain's Private Proof-of-Stake. Joining it is the most useful thing a node can do right now.

> ⚠️ **Officially there are no rewards.** The Logos FAQ says testnet tokens have no value and participation creates no right to future tokens. The only paid programme is λPrize, for developers. Run this because it's cheap and you're curious, not because an airdrop is promised.

---

## How it works

```
  ┌──────────────┐  install.sh  ┌──────────────┐    IBD      ┌──────────────┐
  │   VPS        │ ───────────▶ │  logosctl +  │ ──────────▶ │ Prolonged    │
  │ Ubuntu 24.04 │              │  3 modules   │  (~15 min)  │ Bootstrap    │
  └──────────────┘              └──────┬───────┘             └──────┬───────┘
                                       │ faucet (own keys)          │ Online
                                       ▼                            ▼
                                ┌──────────────┐  every 20m  ┌──────────────┐
                                │  funds land  │ ──────────▶ │ Blend joined │
                                │  as notes    │  timer      │ automatically│
                                └──────────────┘             └──────────────┘
```

**You don't need a wallet.** The node generates its own keys (`keystore.yaml`), and the faucet funds those keys directly.

---

## 1. Get a server

Logos doesn't publish hardware minimums for v0.2.1. Measured on a 6 vCPU / 12 GB VPS after the first hour:

| | Usage |
|---|---|
| RAM | ~0.3 GB |
| Disk | ~350 MB |
| CPU | light |

Any small always-on Linux x86_64 VPS works. It's happy next to other nodes.

## 2. Install

```bash
git clone https://github.com/getcakedieyoungx/logos-node-guide.git
cd logos-node-guide
sudo bash scripts/install.sh            # public IP is auto-detected
# or: sudo bash scripts/install.sh <public-ip>
```

What it does:

1. Downloads `logosctl` and **verifies both SHA-256 checksums** from the official guide.
2. Creates a dedicated `logos` system user under `/var/lib/logos-node`.
3. Installs the three modules at the **exact versions and root hashes** pinned by the official guide.
4. Lets the node generate its own config and keys (`user_config.yaml`, `keystore.yaml`, mode 600).
5. Installs three systemd units:
   - `logos-node.service`: the daemon, restarts on failure, starts on boot
   - `logos-bootstrap.service`: loads and starts blockchain, storage and delivery once the daemon answers
   - `logos-blend-join.timer`: every 20 min, joins Blend once the node is Online and funded, re-requesting faucet funds until then. It stops for good after a successful join.
6. Opens the firewall ports, caps journald at 200 MB, and requests faucet funds for the node's LeaderFunding, BlendZk and SdpFunding keys.

## 3. Check it

```bash
sudo bash scripts/status.sh
```

```
services:  node=active  blend-timer=active
chain:     {"mode":"Bootstrapping","height":51846,"slot":1583034}
modules:   storage_module, package_downloader, package_manager, delivery_module, capability_module, blockchain_module
blend:     not yet (the timer retries every 20 min)
```

What the phases mean:

| Mode / phase | Meaning |
|---|---|
| `Bootstrapping` + IBD | downloading the chain |
| `Bootstrapping` + `ProlongedBootstrapPeriod` | **caught up**, in a deliberate waiting period. Height stays flat here. That's normal, not stuck. |
| `Online` | fully participating. The Blend timer joins on its next run. |

Phase and peer details: `curl -s 127.0.0.1:8080/cryptarchia/info` and `curl -s 127.0.0.1:8080/network/info`.

Funds received in epoch N count for block production from epoch **N+2**, and a Blend declaration becomes active two epochs after it lands. Give it time.

## 4. Back up the node's keys

The node's identity is `/var/lib/logos-node/keystore.yaml`. From your own computer:

```bash
scp root@<server-ip>:/var/lib/logos-node/keystore.yaml ./logos-keystore-backup.yaml
```

It contains secret keys. Don't share it and don't paste it anywhere.

---

## Useful commands

```bash
sudo bash scripts/status.sh                         # health
journalctl -u logos-bootstrap -n 50 --no-pager      # module start output
journalctl -u logos-blend-join -n 20 --no-pager     # Blend join attempts
sudo systemctl restart logos-node                   # restart everything
tail -f /var/lib/logos-node/.logosctl/logs/daemon.log
```

## Ports

| Port | Module | Exposure |
|---|---|---|
| 3000/udp | blockchain P2P | public |
| 3400/udp (from `user_config.yaml`) | Blend | public |
| 8090/udp, 8091/tcp | storage | public |
| 9000/udp, 30303/tcp | delivery | public |
| 8080/tcp | node API | **loopback only** |

9000/**udp** doesn't clash with a service using 9000/**tcp**. They are different protocols.

## Updating to a new release set

When Logos announces a new release set, open the [Node Operator Guide](https://roadmap.logos.co/testnets/logos-node-operator-guide), copy the new versions and root hashes into the top of `scripts/install.sh`, and follow the release notes. Some releases start a **new genesis**, which needs an empty `state/` directory. Your keys can stay.

## FAQ

**Height hasn't moved in an hour.** Check the phase. `ProlongedBootstrapPeriod` means you're at the tip and waiting, see step 3.

**Faucet said `queued` but I have no notes.** Notes only show once the node has synced the blocks that contain them. The timer re-requests anything still empty.

**Lots of `DBG` lines from delivery_module in the daemon log.** Harmless. The log rotates at ~10 MB.

---

## Links

- Node Operator Guide: https://roadmap.logos.co/testnets/logos-node-operator-guide
- Testnet v0.2 announcement: https://blog.logos.co/article/testnet-v02-live
- Docs: https://docs.logos.co
- Telegram group: https://t.me/getcakedieyoungx

## Disclaimer

Community guide, not affiliated with Logos or IFT. Testnet tokens have no value and participation earns no rights. Scripts are provided as-is. Read them before running anything as root.

MIT License
