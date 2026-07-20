# Auto-Proxy

One-click automated proxy tool based on Clash/Mihomo kernel.

Download subscription config → Start proxy core → Set system proxy → Auto shutdown when done.

> **Use Case:** Provides automatic network proxy for AI coding agents like [OpenCode](https://github.com/anomalyco/opencode), [OpenClaw](https://github.com/anomalyco/openclaw), etc. When the agent encounters network timeouts during `webfetch`, `winget install`, or `git clone`, it automatically starts the proxy, completes the task, then shuts down.

## Features

- **Fully Automated**: One command handles everything from subscription to proxy setup
- **Auto Cleanup**: Shuts down proxy after task completion, no resource waste
- **Smart Detection**: Automatically finds the latest Mihomo core on your system
- **Cross-Tool Compatible**: Sets both system proxy and HTTP_PROXY environment variables — works for browsers and CLI tools
- **Secure**: Disables LAN access by default (allow-lan: false)

## Prerequisites

- **Mihomo Core** (clash-meta): Recommended to install via winget for the latest version
  ```bash
  winget install MetaCubeX.Mihomo
  ```
- **A working Clash subscription URL** (from your VPN provider or self-hosted nodes)

Mihomo Party / Clash for Windows users already have the core bundled — the script will auto-detect it.

## Quick Start

### 1. Create Config File

Copy `config.example.json` to `config.json` and fill in your subscription URL:

```json
{
  "subscription_url": "https://your-provider.com/subscribe?token=xxx"
}
```

| Field | Description | Required |
|-------|-------------|----------|
| `subscription_url` | Clash subscription URL | Yes |
| `proxy_host` | Proxy listen address | No, defaults to 127.0.0.1 |
| `proxy_port` | Proxy listen port | No, defaults to 7890 |
| `mihomo_path` | Path to Mihomo executable | No, auto-detect |

### 2. Start Proxy

```bash
.\auto-proxy.ps1 start
```

The script will automatically:
1. Download Clash config from subscription URL
2. Optimize config (correct port, disable LAN, reduce log verbosity)
3. Start Mihomo core process
4. Wait for proxy to be ready
5. Enable system proxy

### 3. Get to Work

Once the proxy is running, browsers and CLI tools will route through it automatically.

### 4. Stop Proxy

```bash
.\auto-proxy.ps1 stop
```

## Commands

### auto-proxy.ps1 (Recommended: Full Auto)

| Command | Description |
|---------|-------------|
| `start` | One-click: download config → start Mihomo → enable proxy |
| `stop` | Disable proxy + shutdown Mihomo process |
| `status` | Show proxy status, Mihomo process, and port connectivity |
| `test` | Test if proxy is working (accesses Google) |

### proxy.ps1 (Alternative: Manual Mode)

Use when Clash is already running (e.g. via GUI). Only manages proxy on/off:

| Command | Description |
|---------|-------------|
| `enable` | Enable system proxy + set HTTP_PROXY env vars |
| `disable` | Disable system proxy + clear env vars |
| `status` | Check proxy status and port connectivity |
| `test` | Test proxy connection |

## Use Cases

### Scenario 1: Daily Development

```bash
# When you need to download a GitHub Release
.\auto-proxy.ps1 start
curl -LO https://github.com/xxx/yyy/releases/latest/download/package.zip
.\auto-proxy.ps1 stop
```

### Scenario 2: Script Integration

```batch
@echo off
powershell -File auto-proxy.ps1 start
pip install some-blocked-package
powershell -File auto-proxy.ps1 stop
```

### Scenario 3: AI Agent Automation

Configure your AI coding agent to automatically run `auto-proxy.ps1 start` on network timeout, and `stop` when done. See the [OpenCode integration example](#) for details.

## Architecture

```
auto-proxy.ps1        ← Full auto solution (recommended)
  ├── Download subscription config
  ├── Start Mihomo core
  ├── Enable system proxy
  └── Stop Mihomo core

proxy.ps1             ← Manual mode (when Clash already running)
  ├── Enable/disable system proxy
  └── Set/clear env variables
```

## Workflow

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Download     │ ──▶ │  Optimize     │ ──▶ │ Start Mihomo  │
│  Config       │     │  Config       │     │ Core (bg)     │
│  (Clash UA)   │     │ (port+secure) │     │               │
└─────────────┘     └──────────────┘     └──────┬────────┘
                                                 │
                   ┌──────────────┐              │
                   │  Done: stop   │ ◀───────────┘
                   │  proxy+core   │     ┌──────────────┐
                   └──────────────┘     │ Wait for port  │
                                        │ (poll :7890)  │
                                        └──────┬────────┘
                                               │
                                        ┌──────▼───────┐
                                        │ Enable System  │
                                        │ Proxy + Env    │
                                        └───────────────┘
```

## FAQ

**Q: Startup fails with "unsupport proxy type: anytls"?**
A: Your Mihomo core is too old. Install the latest via `winget install MetaCubeX.Mihomo`.

**Q: Subscription download fails (403 Forbidden)?**
A: The script uses `User-Agent: Clash` header. If it still fails, check if your subscription URL is still valid.

**Q: Proxy is running but browser can't access blocked sites?**
A: Check if the Mihomo core supports the protocols in your subscription config. Run `mihomo -f mihomo-config.yaml` manually to see logs.

**Q: Will this conflict with Mihomo Party / Clash for Windows?**
A: If the port is already in use (GUI running), the script only sets system proxy without starting a new process.

## Technical Notes

- **Proxy Port**: Default 7890 (HTTP/SOCKS5 mixed port)
- **API Port**: Default 9090 (used for graceful shutdown)
- **Config File**: Generated as `mihomo-config.yaml` on first run
- **PID File**: `mihomo.pid` (for process management)
- **Security**: Default `allow-lan: false`, localhost only

## References

- [Mihomo (Clash Meta)](https://github.com/MetaCubeX/mihomo) — The proxy core kernel
- [OpenCode](https://github.com/anomalyco/opencode) — AI coding agent this tool was designed for
- [Clash](https://github.com/Dreamacro/clash) — The original Clash project

## Author

**Tianshan (tianshan233)** — [GitHub](https://github.com/tianshan233)

Co-authored with **Vanilla (OpenCode AI Agent)**.

---

## License

MIT
