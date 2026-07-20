# Auto-Proxy

一键自动化科学上网工具，基于 Clash/Mihomo 内核。

自动下载订阅配置 → 启动代理核心 → 设置系统代理 → 用完自动关闭。

> **适用场景：** 为 AI 编码助手（[OpenCode](https://github.com/anomalyco/opencode)、[OpenClaw](https://github.com/anomalyco/openclaw) 等）提供自动网络代理。当 Agent 执行 `webfetch`、`winget install`、`git clone` 等操作遇到网络超时时，自动启动代理完成后关闭。

## 功能特点

- **全自动**：一条命令搞定，从订阅到代理全流程自动化
- **用完即关**：任务完成后自动关闭代理，不浪费系统资源
- **智能检测**：自动查找系统中最新的 Mihomo 核心
- **跨工具兼容**：同时设置系统代理和 HTTP_PROXY 环境变量，浏览器和命令行工具都能用
- **安全模式**：默认禁用局域网共享（allow-lan）

## 前置要求

- **Mihomo 核心**（clash-meta）：推荐通过 winget 安装最新版
  ```bash
  winget install MetaCubeX.Mihomo
  ```
- **可用的 Clash 订阅链接**（机场或自建节点）

Mihomo Party / Clash for Windows 用户通常已自带核心，脚本会自动检测。

## 快速开始

### 1. 创建配置文件

复制 `config.example.json` 为 `config.json`，填入你的订阅链接：

```json
{
  "subscription_url": "https://your-provider.com/subscribe?token=xxx"
}
```

| 字段 | 说明 | 必填 |
|------|------|------|
| `subscription_url` | Clash 订阅链接 | 是 |
| `proxy_host` | 代理监听地址 | 否，默认 127.0.0.1 |
| `proxy_port` | 代理监听端口 | 否，默认 7890 |
| `mihomo_path` | Mihomo 核心路径 | 否，默认自动查找 |

### 2. 启动代理

```bash
.\auto-proxy.ps1 start
```

脚本会自动：
1. 从订阅链接下载 Clash 配置
2. 优化配置（端口修正、禁用 LAN、降低日志）
3. 启动 Mihomo 核心进程
4. 等待代理就绪
5. 设置系统代理

### 3. 开始使用

代理启动后，浏览器和命令行工具自动走代理。

### 4. 关闭代理

```bash
.\auto-proxy.ps1 stop
```

## 命令说明

### auto-proxy.ps1（推荐：全自动）

| 命令 | 说明 |
|------|------|
| `start` | 一键启动：下载订阅 → 启动 Mihomo → 设置代理 |
| `stop` | 关闭代理 + 停止 Mihomo 进程 |
| `status` | 查看代理状态、Mihomo 进程、端口连通性 |
| `test` | 测试代理是否可用（访问 Google） |

### proxy.ps1（备选：手动管理）

如果 Clash 已经在运行（如通过 GUI 启动），只需手动管理代理开关：

| 命令 | 说明 |
|------|------|
| `enable` | 开启系统代理 + 设置 HTTP_PROXY 环境变量 |
| `disable` | 关闭系统代理 + 清除环境变量 |
| `status` | 查看代理状态和端口连通性 |
| `test` | 测试代理连接 |

## 使用场景

### 场景 1：日常开发

```bash
# 需要下载 GitHub Release 时
.\auto-proxy.ps1 start
curl -LO https://github.com/xxx/yyy/releases/latest/download/package.zip
.\auto-proxy.ps1 stop
```

### 场景 2：脚本集成

```batch
@echo off
powershell -File auto-proxy.ps1 start
pip install some-blocked-package
powershell -File auto-proxy.ps1 stop
```

### 场景 3：AI Agent 自动化

在 AI 编码助手中配置：网络请求超时时自动执行 `auto-proxy.ps1 start`，完成后 `stop`。

## 脚本间关系

```
auto-proxy.ps1          ← 全自动方案（推荐）
  ├── 下载订阅配置
  ├── 启动 Mihomo 核心
  ├── 设置系统代理
  └── 停止 Mihomo 核心

proxy.ps1               ← 手动方案（Clash 已在运行时用）
  ├── 开启/关闭系统代理
  └── 设置/清除环境变量
```

## 工作流程

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│ 下载订阅配置  │ ──▶ │  优化配置文件  │ ──▶ │ 启动Mihomo核心 │
│ (Clash UA)   │     │ (端口+安全)   │     │ (后台进程)     │
└─────────────┘     └──────────────┘     └──────┬───────┘
                                                 │
                   ┌──────────────┐              │
                   │  任务完成，关闭  │ ◀───────────┘
                   │  代理+停止核心  │     ┌──────────────┐
                   └──────────────┘     │  等待端口就绪   │
                                        │ (轮询7890端口) │
                                        └──────┬───────┘
                                               │
                                        ┌──────▼───────┐
                                        │  设置系统代理   │
                                        │  + 环境变量    │
                                        └──────────────┘
```

## 常见问题

**Q: 启动报错 "unsupport proxy type: anytls"？**
A: Mihomo 核心版本太旧。用 `winget install MetaCubeX.Mihomo` 安装最新版。

**Q: 下载订阅失败（403 Forbidden）？**
A: 脚本使用 `User-Agent: Clash` 请求头。如果仍失败，检查订阅链接是否有效。

**Q: 代理启动后浏览器还是不能翻墙？**
A: 检查 Mihomo 核心是否支持订阅配置中的协议类型。可手动运行 `mihomo -f mihomo-config.yaml` 查看日志。

**Q: 会和 Mihomo Party / Clash for Windows 冲突吗？**
A: 如果检测到端口已被占用（GUI 已在运行），脚本只设置系统代理，不会启动新进程。

## 技术说明

- **代理端口**: 默认 7890（HTTP/SOCKS5 混合端口）
- **API 端口**: 默认 9090（用于优雅关闭）
- **配置文件**: 运行后生成 `mihomo-config.yaml`
- **PID 文件**: `mihomo.pid`（用于进程管理）
- **安全**: 默认 `allow-lan: false`，仅本机使用
- **注册表刷新**: 修改代理设置后通过 WinINet API 强制刷新，确保开关立即生效（无需手动去 LAN 设置操作）

## 参考资料

- [Mihomo (Clash Meta)](https://github.com/MetaCubeX/mihomo) — 代理核心内核
- [OpenCode](https://github.com/anomalyco/opencode) — AI 编码助手，本工具为其网络超时场景设计
- [Clash](https://github.com/Dreamacro/clash) — 原始 Clash 项目

## 作者

**天山酱 (tianshan233)** — [GitHub](https://github.com/tianshan233)

由 AI 助手 **香草 (OpenCode Agent)** 协助编写与维护。

---

## License

MIT
