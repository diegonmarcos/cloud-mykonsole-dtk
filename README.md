# Ops Tooling

Infrastructure operations toolkit — unified dashboard, sync engine, and build templates for managing the cloud/unix/front stack.

---

## Table of Contents

### A) Documentation Overview
- [A.1 Cloud Connect Dashboard](#a1-cloud-connect-dashboard)
- [A.2 Sync Engine](#a2-sync-engine)
- [A.3 Build Templates](#a3-build-templates)
- [A.4 Utility Scripts](#a4-utility-scripts)

### B) Architectural Design
- [B.1 Repository Structure](#b1-repository-structure)
- [B.2 Connect Configuration](#b2-connect-configuration)
- [B.3 Sync Engine Design](#b3-sync-engine-design)
- [B.4 Build Engine Templates](#b4-build-engine-templates)

---

## A) Documentation Overview

### A.1 Cloud Connect Dashboard

`a-cloud-connect/connect.sh` — unified TUI dashboard for managing:

- **Git**: Status, pull, push across all repos (cloud, unix, vault, front, tools)
- **FUSE Mounts**: rclone mounts for cloud storage
- **Mesh**: WireGuard VPN status across 8 VMs
- **Data Servers**: Local data services
- **Web Servers**: Dev server management
- **Sync**: Cross-machine file synchronization

```bash
./a-cloud-connect/connect.sh
```

### A.2 Sync Engine

`a-sync/sync.sh` — rclone + Git synchronization orchestrator. Manages cross-machine state for all repos.

### A.3 Build Templates

`a-build/` — canonical `build.sh` templates for each stack:

| Template | Target |
|----------|--------|
| `cloud-engine/build.sh` | Cloud service engine |
| `cloud-orchestrator/build.sh` | Cloud root orchestrator |
| `front-engine/build.sh` | Front-end project engine |
| `front-orchestrator/build.sh` | Front-end root orchestrator |
| `nix-hm/build.sh` | Home Manager builds |

### A.4 Utility Scripts

| Script | Purpose |
|--------|---------|
| `b-scripts/oracle-arm-retry.sh` | Retry OCI ARM instance creation |
| `b-scripts/surface-trackpad-reset.sh` | Reset Surface Pro trackpad |

---

## B) Architectural Design

### B.1 Repository Structure

```
tools/
├── a-build/              Build engine templates (symlinked to repos)
│   ├── cloud-engine/
│   ├── cloud-orchestrator/
│   ├── front-engine/
│   ├── front-orchestrator/
│   └── nix-hm/
│
├── a-cloud-connect/      Unified dashboard TUI (~6K lines)
│   ├── connect.sh        Main entry point
│   ├── connect-settings.json    Profiles, paths, deps
│   ├── connect-mesh.json        VM definitions (8 VMs)
│   ├── connect-git.json         Git repo configs
│   ├── connect-hm-flakes.json   Home Manager VM targets
│   ├── connect-sync.json        Rclone sync rules
│   ├── connect-fuse-drives.json FUSE mount configs
│   ├── connect-data-servers.json Data server configs
│   ├── connect-web-servers.json  Web server configs
│   └── libs/             Helper libraries (MD renderer, web utils)
│
├── a-sync/               Sync engine
│   └── sync.sh           Rclone + Git orchestrator
│
├── b-scripts/            Utility scripts
│
└── z-archive/            Legacy tools (gcl.sh, old mesh/mount scripts)
```

### B.2 Connect Configuration

The dashboard reads JSON config files to discover infrastructure:

| Config File | Content |
|-------------|---------|
| `connect-mesh.json` | 8 VMs: IPs, WireGuard IPs, services per VM |
| `connect-git.json` | 5 repos: cloud, unix, vault, front, tools |
| `connect-hm-flakes.json` | Home Manager deployment targets |
| `connect-sync.json` | Rclone sync rules (sources, destinations) |
| `connect-fuse-drives.json` | FUSE mount definitions (cloud storage) |

### B.3 Sync Engine Design

`sync.sh` manages bidirectional sync between machines:

1. **Git repos**: Pull/push across all 5 repos
2. **Rclone**: Cloud storage sync (configurable rules)
3. **SOPS**: Age encryption for secrets during sync

### B.4 Build Engine Templates

The `a-build/` directory contains the canonical `build.sh` templates. Each repo (cloud, front, unix) symlinks its engine from here. When the engine is updated, all repos pick up the change.

---

**Last Updated**: 2026-03-18
