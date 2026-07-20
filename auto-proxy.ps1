<#
.SYNOPSIS
    Auto-Proxy - One-click automated proxy setup using Clash/Mihomo
.DESCRIPTION
    Automatically downloads subscription config, starts Mihomo core,
    sets up system proxy, and cleans up when done.
    
    Designed for users behind GFW who need seamless proxy access.
    
.EXAMPLE
    .\auto-proxy.ps1 start
    .\auto-proxy.ps1 stop
    .\auto-proxy.ps1 status
    .\auto-proxy.ps1 test
.NOTES
    Requires: Mihomo (clash-meta) core installed via winget or bundled.
    Subscribed URL must return a valid Clash YAML config.
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "stop", "status", "test")]
    [string]$Action = "status"
)

# ============================================================================
# CONFIGURATION - Load from config.json or use defaults
# ============================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"
$configExist = Test-Path $configPath

# Proxy settings
$proxyHost = "127.0.0.1"
$proxyPort = 7890
$subscriptionUrl = ""

# Load config file if it exists
if ($configExist) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($config.subscription_url) { $subscriptionUrl = $config.subscription_url }
        if ($config.proxy_host) { $proxyHost = $config.proxy_host }
        if ($config.proxy_port) { $proxyPort = [int]$config.proxy_port }
    } catch {
        Write-Host "[AutoProxy] WARNING: Failed to parse config.json, using defaults" -ForegroundColor Yellow
    }
}

$proxyServer = "${proxyHost}:${proxyPort}"

# Runtime files (stored in script directory)
$pidFile = Join-Path $scriptDir "mihomo.pid"
$localConfigFile = Join-Path $scriptDir "mihomo-config.yaml"

# System proxy registry path (Windows only)
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# ============================================================================
# MIHOMO CORE DETECTION - Find mihomo executable automatically
# ============================================================================

function Find-MihomoPath {
    <#
    .SYNOPSIS
        Locate mihomo (clash-meta) executable on the system.
    .DESCRIPTION
        Search order:
        1. config.json "mihomo_path" if specified
        2. Winget-installed version (latest, supports all protocols)
        3. Mihomo Party GUI bundled version
        4. PATH environment variable
    #>
    
    # Priority 1: Explicit path from config
    if ($configExist -and $config.mihomo_path -and $config.mihomo_path -ne "auto") {
        if (Test-Path $config.mihomo_path) {
            return $config.mihomo_path
        }
    }

    # Priority 2: Winget installation (v1.19.29+, supports anytls)
    $wingetDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $wingetDir) {
        $wingetMihomo = Get-ChildItem -Path $wingetDir -Recurse -Filter "mihomo-windows-amd64.exe" -ErrorAction SilentlyContinue | 
            Select-Object -First 1 -ExpandProperty FullName
        if ($wingetMihomo) { return $wingetMihomo }
    }

    # Priority 3: Mihomo Party bundled versions
    $partyPaths = @(
        "C:\Program Files\Mihomo Party\resources\sidecar\mihomo-alpha.exe",
        "C:\Program Files\Mihomo Party\resources\sidecar\mihomo.exe"
    )
    foreach ($path in $partyPaths) {
        if (Test-Path $path) { return $path }
    }

    # Priority 4: Check PATH
    $pathMihomo = (Get-Command "mihomo" -ErrorAction SilentlyContinue).Source
    if ($pathMihomo) { return $pathMihomo }
    $pathMihomoExe = (Get-Command "mihomo-windows-amd64" -ErrorAction SilentlyContinue).Source
    if ($pathMihomoExe) { return $pathMihomoExe }

    return $null
}

$mihomoPath = Find-MihomoPath

# WinINet P/Invoke — forces Windows to immediately apply proxy registry changes
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinInet {
    public const int INTERNET_OPTION_SETTINGS_CHANGED = 39;
    public const int INTERNET_OPTION_REFRESH = 37;
    [DllImport("wininet.dll", SetLastError = true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
    public static void RefreshProxy() {
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_SETTINGS_CHANGED, IntPtr.Zero, 0);
        InternetSetOption(IntPtr.Zero, INTERNET_OPTION_REFRESH, IntPtr.Zero, 0);
    }
}
"@

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-Status {
    param([string]$Message)
    Write-Host "[AutoProxy] $Message" -ForegroundColor Cyan
}

function Write-Error {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
}

function Enable-SystemProxy {
    <#
    .SYNOPSIS
        Enable Windows system proxy and set HTTP_PROXY environment variables.
    .DESCRIPTION
        Modifies Internet Settings registry and sets both process-level
        and user-level HTTP_PROXY/HTTPS_PROXY environment variables.
    #>
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1 -Type DWord | Out-Null
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyServer | Out-Null
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>" | Out-Null

    # Force Windows to apply registry changes immediately
    [WinInet]::RefreshProxy()

    # Process-level env (current shell)
    $env:HTTP_PROXY = "http://${proxyServer}"
    $env:HTTPS_PROXY = "http://${proxyServer}"
    $env:NO_PROXY = "localhost,127.0.0.1,.local"

    # User-level env (persists across new shells)
    [Environment]::SetEnvironmentVariable("HTTP_PROXY", "http://${proxyServer}", "User")
    [Environment]::SetEnvironmentVariable("HTTPS_PROXY", "http://${proxyServer}", "User")
    [Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1,.local", "User")

    Write-Status "System proxy enabled -> http://${proxyServer}"
}

function Disable-SystemProxy {
    <#
    .SYNOPSIS
        Disable Windows system proxy and clear HTTP_PROXY variables.
    #>
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -Type DWord | Out-Null

    # Force Windows to apply registry changes immediately
    [WinInet]::RefreshProxy()

    Remove-Item Env:\HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue

    [Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")

    Write-Status "System proxy disabled"
}

function Test-ProxyReady {
    <#
    .SYNOPSIS
        Wait for the proxy port to become available.
    .PARAMETER TimeoutSec
        Maximum seconds to wait (default: 30).
    .RETURNS
        $true if proxy is ready, $false if timed out.
    #>
    param([int]$TimeoutSec = 30)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            $conn = [System.Net.Sockets.TcpClient]::new()
            $task = $conn.ConnectAsync($proxyHost, $proxyPort)
            if ($task.Wait(2000) -and $conn.Connected) {
                $conn.Close()
                return $true
            }
            $conn.Close()
        }
        catch {}
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Download-Subscription {
    <#
    .SYNOPSIS
        Download Clash subscription config using proper User-Agent.
    .DESCRIPTION
        Most subscription services require a "Clash" User-Agent header.
        Returns the raw YAML config content.
    .PARAMETER Url
        The subscription URL.
    #>
    param([string]$Url)

    Write-Status "Downloading subscription config..."
    $headers = @{
        "User-Agent" = "Clash"
        "Accept"      = "*/*"
    }
    try {
        $response = Invoke-WebRequest -Uri $Url -Headers $headers -TimeoutSec 20 -UseBasicParsing
        return $response.Content
    }
    catch {
        throw "Failed to download subscription: $($_.Exception.Message)"
    }
}

function Optimize-Config {
    <#
    .SYNOPSIS
        Optimize the Clash config for local use.
    .DESCRIPTION
        - Sets the correct mixed-port
        - Disables allow-lan for security
        - Reduces log level
    #>
    param([string]$RawConfig)

    # Ensure correct port
    $RawConfig = $RawConfig -replace "mixed-port:\s*\d+", "mixed-port: ${proxyPort}"
    # Disable LAN access (security)
    $RawConfig = $RawConfig -replace "allow-lan:\s*true", "allow-lan: false"
    # Quiet logging
    if ($RawConfig -match "log-level:") {
        $RawConfig = $RawConfig -replace "log-level:\s*\w+", "log-level: warning"
    }

    return $RawConfig
}

# ============================================================================
# COMMAND HANDLERS
# ============================================================================

function Start-Proxy {
    <#
    .SYNOPSIS
        Full automatic proxy startup: download config -> start mihomo -> enable proxy.
    #>

    # Check if proxy port is already in use (e.g. user started Clash manually)
    try {
        $conn = [System.Net.Sockets.TcpClient]::new()
        $task = $conn.ConnectAsync($proxyHost, $proxyPort)
        if ($task.Wait(1000) -and $conn.Connected) {
            $conn.Close()
            Write-Status "Proxy port ${proxyPort} already active (GUI or another instance running)"
            Enable-SystemProxy
            Write-Status "Proxy enabled via existing process"
            return
        }
        $conn.Close()
    }
    catch {}

    # Check for subscription URL
    if (-not $subscriptionUrl) {
        Write-Error "No subscription_url configured. Please create config.json with your subscription URL."
        Write-Host ""
        Write-Host "Example config.json:" -ForegroundColor Yellow
        Write-Host @'
{
  "subscription_url": "https://your-provider.com/subscribe?token=xxx"
}
'@
        return
    }

    # Check for mihomo core
    if (-not $mihomoPath) {
        Write-Error "Mihomo core not found."
        Write-Host ""
        Write-Host "Install it via winget:" -ForegroundColor Yellow
        Write-Host "  winget install MetaCubeX.Mihomo"
        Write-Host ""
        Write-Host "Or specify path in config.json:" -ForegroundColor Yellow
        Write-Host '  "mihomo_path": "C:\\path\\to\\mihomo.exe"'
        return
    }

    # Download and optimize subscription config
    try {
        $rawConfig = Download-Subscription -Url $subscriptionUrl
        $optimized = Optimize-Config -RawConfig $rawConfig
        Set-Content -Path $localConfigFile -Value $optimized -Encoding UTF8
        Write-Status "Config saved to ${localConfigFile} ($($optimized.Length) bytes)"
    }
    catch {
        Write-Error $_.Exception.Message
        return
    }

    # Start mihomo core process
    Write-Status "Starting mihomo core (${mihomoPath})..."
    $proc = Start-Process -FilePath $mihomoPath -ArgumentList "-f `"${localConfigFile}`"" -WindowStyle Hidden -PassThru
    $proc.Id | Out-File -FilePath $pidFile -NoNewline

    # Wait for proxy port to be ready
    Write-Status "Waiting for proxy to be ready..."
    if (Test-ProxyReady -TimeoutSec 30) {
        Enable-SystemProxy
        Write-Status "ALL DONE! Proxy running | PID: $($proc.Id) | Port: ${proxyPort}"
    }
    else {
        Write-Error "Proxy did not start in time. Check mihomo compatibility with your subscription config."
        # Cleanup failed process
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Remove-Item $pidFile -ErrorAction SilentlyContinue
    }
}

function Stop-Proxy {
    <#
    .SYNOPSIS
        Stop proxy: disable system proxy and kill mihomo process.
    #>

    # Disable system proxy first
    Disable-SystemProxy

    # Try graceful shutdown via Mihomo API (external-controller)
    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:9090" -TimeoutSec 2 -UseBasicParsing
        try {
            $null = Invoke-RestMethod -Uri "http://127.0.0.1:9090/configs" -Method Delete -TimeoutSec 3
        }
        catch {}
    }
    catch {}

    # Kill by PID file
    if (Test-Path $pidFile) {
        $mihomoPid = Get-Content $pidFile
        try {
            Stop-Process -Id $mihomoPid -Force -ErrorAction Stop
            Write-Status "Mihomo stopped (PID: $mihomoPid)"
        }
        catch {}
        Remove-Item $pidFile -ErrorAction SilentlyContinue
    }

    # Clean up any remaining mihomo processes (safety net)
    Get-Process -Name "mihomo*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Show-Status {
    <#
    .SYNOPSIS
        Display current proxy and mihomo status.
    #>

    # System proxy status
    $proxyEnabled = (Get-ItemProperty -Path $regPath -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    Write-Host "System proxy    : $(if ($proxyEnabled -eq 1) { 'ON' } else { 'OFF' })"
    if ($proxyEnabled -eq 1) {
        $server = (Get-ItemProperty -Path $regPath -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
        Write-Host "Proxy address   : $server"
    }
    Write-Host ""

    # Mihomo process status
    Write-Host "Mihomo process  :"
    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile
        try {
            $null = Get-Process -Id $savedPid -ErrorAction Stop
            Write-Host "  PID ${savedPid} - Running (managed by auto-proxy)" -ForegroundColor Green
        }
        catch {
            Write-Host "  PID ${savedPid} - Not running (stale PID file)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  Not managed by auto-proxy"
    }

    # Port connectivity check
    Write-Host ""
    Write-Host "Port ${proxyPort}    :"
    try {
        $conn = [System.Net.Sockets.TcpClient]::new()
        $task = $conn.ConnectAsync($proxyHost, $proxyPort)
        if ($task.Wait(2000) -and $conn.Connected) {
            Write-Host "  Connected - Proxy active" -ForegroundColor Green
            $conn.Close()
        }
        else {
            Write-Host "  Not reachable" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  Not reachable" -ForegroundColor Red
    }

    # Mihomo path
    Write-Host ""
    Write-Host "Mihomo core     : $(if ($mihomoPath) { $mihomoPath } else { 'NOT FOUND' })"
    Write-Host "Config file     : $(if (Test-Path $localConfigFile) { $localConfigFile } else { 'not generated yet' })"
}

function Test-ProxyConnection {
    <#
    .SYNOPSIS
        Test if the proxy is working by accessing Google.
    #>
    Write-Status "Testing proxy connection to google.com..."
    try {
        $result = Invoke-WebRequest -Uri "https://www.google.com" -Proxy "http://${proxyServer}" -TimeoutSec 10 -UseBasicParsing
        Write-Host "SUCCESS! Google reachable (HTTP $($result.StatusCode))" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Tip: Run 'auto-proxy.ps1 start' first, or check if mihomo supports your subscription config."
    }
}

# ============================================================================
# MAIN DISPATCH
# ============================================================================

switch ($Action) {
    "start"  { Start-Proxy }
    "stop"   { Stop-Proxy }
    "status" { Show-Status }
    "test"   { Test-ProxyConnection }
}
