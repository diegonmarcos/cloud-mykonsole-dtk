```
╔═══════════════════════════════════════════════════════════════╗
║  ██████╗ ████████╗██╗  ██╗                                    ║
║  ██╔══██╗╚══██╔══╝██║ ██╔╝                                    ║
║  ██║  ██║   ██║   █████╔╝   Diego's Toolkit                   ║
║  ██║  ██║   ██║   ██╔═██╗   OS-agnostic CLI                   ║
║  ██████╔╝   ██║   ██║  ██╗                                    ║
║  ╚═════╝    ╚═╝   ╚═╝  ╚═╝                                    ║
║                                                               ║
║  Aliases · Containers · Connect · Others · Help               ║
╚═══════════════════════════════════════════════════════════════╝
```

# DTK — Diego's Toolkit

Unified CLI for managing aliases, containers, infrastructure, and dev toolchains across NixOS, Arch, Debian, Fedora, macOS, and Termux.

```bash
./dtk.sh           # interactive menu
./dtk.sh 16        # shortcode: aliases → git
./dtk.sh aliases   # direct command
```

---

## Menu Structure

```
1) aliases        2) containers    3) connect       4) others        5) help
11 modern-cli    21 deb-nix       31 git            41 ssh            usage
12 navigation    22 deb-apt       32 mounts         42 git-clone      commands
13 safety        23 cli           33 sync           43 install
14 python        24 gui           34 servers        44 commands
15 system        25 tty                             45 info
16 git                                              46 engines
17 docker
18 session
19 web-terminal
1a misc
1b functions
```

---

## Repository Structure

```
tools/
├── dtk.sh                    Main entry point — interactive + CLI
│
├── 1-aliases/                Alias reference (data-driven)
│   ├── aliases.json          Source of truth — all aliases by category
│   ├── aliases.sh            Generator: JSON → Markdown
│   ├── aliases.md.tpl        Markdown template
│   └── aliases.md            Generated reference (auto)
│
├── 2-containers/             Container profiles
│   └── containers.sh         Launcher (delegates to dtk.sh)
│
├── 3-connect/                Cloud Connect Dashboard TUI
│   ├── connect.sh            Main entry point
│   ├── connect-settings.json Profiles, paths, deps
│   ├── connect-mesh.json     VM definitions (WireGuard mesh)
│   ├── connect-git.json      Git repo configs
│   ├── connect-hm-flakes.json Home Manager VM targets
│   ├── connect-sync.json     Rclone sync rules
│   ├── connect-fuse-drives.json FUSE mount configs
│   ├── connect-data-servers.json Data server configs
│   ├── connect-web-servers.json Web server configs
│   └── libs/                 Helper libraries (MD renderer, web utils)
│
├── 4-others/                 Ops utilities
│   ├── 1-ssh/                GCP serial/SSH/rescue
│   ├── 2-git-clone/          Clone all repos
│   ├── 3-install/            Dev toolchain installer
│   ├── 4-commands/           Quick VM commands (iptables, docker, wg)
│   ├── 5-info/               Installed tools check
│   ├── 6-engines/            Build engine templates
│   │   ├── cloud-engine/
│   │   ├── cloud-orchestrator/
│   │   ├── front-engine/
│   │   ├── front-orchestrator/
│   │   ├── nix-hm-desktop/
│   │   ├── nix-hm-desktop-cloud/
│   │   ├── nix-hm-termux/
│   │   └── nix-os-desktop/
│   ├── surface-trackpad-reset.sh
│   └── z-others/             Legacy scripts (archive)
│
├── 5-help/                   Help resources
│
├── hooks/                    Git hooks (core.hooksPath = hooks)
│   └── pre-commit
│
├── cloud-data/               Cloud data submodule
└── front-data/               Front data submodule
```

---

## 1) Aliases

All aliases are defined in `1-aliases/aliases.json` and rendered by `dtk.sh` at runtime. Categories:

| # | Category | Description |
|---|----------|-------------|
| 11 | modern-cli | ls→eza, cat→bat, grep→rg, find→fd, df→duf, du→ncdu |
| 12 | navigation | .., ..., ...., mkcd, mkd |
| 13 | safety | rm -i, cp -i, mv -i |
| 14 | python | py, python, pip, ppy |
| 15 | system | free, ports, myip, cpucap, duh, localip |
| 16 | git | gs, ga, gaa, gc, gcm, gp, gl, gd, gco, gacp |
| 17 | docker | dps, dpsa, dcu, dcd |
| 18 | session | KDE Plasma 6 logout/reboot/poweroff |
| 19 | web-terminal | fish-e (ttyd+tmux on WireGuard), fish-e-stop |
| 1a | misc | c, cls, h, hg, path, reload, welcome |
| 1b | functions | ai-cli, hhelp, extract, backup, serve, fzf bindings |

Generate markdown reference: `./1-aliases/aliases.sh`

## 2) Containers

Pull and run Diego's dev environment containers:

| Image | Description |
|-------|-------------|
| `deb-nix` | Debian 12 + Nix + Home-Manager (full match of desktop flake) |
| `deb-apt` | Debian 12 + apt packages (lightweight) |

Profiles: `cli` (headless), `gui` (desktop integration), `tty` (non-interactive/CI)

```bash
./dtk.sh containers deb-nix cli
```

## 3) Connect

Cloud Connect Dashboard — unified TUI for:
- **Git**: status, pull, push across all repos
- **FUSE Mounts**: rclone cloud storage
- **Mesh**: WireGuard VPN status
- **Data/Web Servers**: local service management
- **Sync**: cross-machine file synchronization

```bash
./dtk.sh connect
```

## 4) Others

| # | Command | Description |
|---|---------|-------------|
| 41 | ssh | GCP serial/SSH/rescue/reset |
| 42 | git-clone | Clone all 5 repos to ~/git |
| 43 | install | Full dev toolchain (Fedora/Arch/Debian/Nix) |
| 44 | commands | Quick VM commands (flush iptables, restart docker/wg) |
| 45 | info | Show all installed tools with versions |
| 46 | engines | Launch build.sh engines (NixOS, home-manager, cloud, front) |

## 5) Help

```bash
./dtk.sh help
```

---

## Navigation

- `b` — back to parent menu
- `q` — quit
- `1-5` — main menu selection
- `11-46` — direct shortcode (e.g. `16` = git aliases)

---

**Last Updated**: 2026-03-30
