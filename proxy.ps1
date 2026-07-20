<#
.SYNOPSIS
    Proxy Manager - Manually manage Windows system proxy settings
.DESCRIPTION
    Use this when Clash/Mihomo is already running (e.g. via GUI).
    For fully automated setup, use auto-proxy.ps1 instead.
    
.EXAMPLE
    .\proxy.ps1 enable   # Turn on system proxy
    .\proxy.ps1 disable  # Turn off system proxy
    .\proxy.ps1 status   # Check proxy status
    .\proxy.ps1 test     # Test if proxy works
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet("enable", "disable", "status", "test")]
    [string]$Action = "status"
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

$proxyHost = "127.0.0.1"
$proxyPort = 7890

# Load config if available
if (Test-Path $configPath) {
    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($config.proxy_host) { $proxyHost = $config.proxy_host }
        if ($config.proxy_port) { $proxyPort = [int]$config.proxy_port }
    }
    catch {}
}

$proxyServer = "${proxyHost}:${proxyPort}"
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

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
# FUNCTIONS
# ============================================================================

function Write-Status {
    param([string]$Message)
    Write-Host "[Proxy] $Message" -ForegroundColor Cyan
}

function Enable-Proxy {
    <#
    .SYNOPSIS
        Enable Windows system proxy.
    .DESCRIPTION
        Sets Internet Settings registry keys to route traffic through
        the Clash/Mihomo proxy. Also sets HTTP_PROXY/HTTPS_PROXY
        environment variables for CLI tools like curl, pip, npm, etc.
    #>

    # System proxy (IE/Edge/Chrome settings)
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 1 -Type DWord | Out-Null
    Set-ItemProperty -Path $regPath -Name ProxyServer -Value $proxyServer | Out-Null
    Set-ItemProperty -Path $regPath -Name ProxyOverride -Value "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>" | Out-Null

    # Force Windows to apply registry changes immediately
    [WinInet]::RefreshProxy()

    # Current process environment
    $env:HTTP_PROXY = "http://${proxyServer}"
    $env:HTTPS_PROXY = "http://${proxyServer}"
    $env:NO_PROXY = "localhost,127.0.0.1,.local"

    # Persistent user environment (for new shells)
    [Environment]::SetEnvironmentVariable("HTTP_PROXY", "http://${proxyServer}", "User")
    [Environment]::SetEnvironmentVariable("HTTPS_PROXY", "http://${proxyServer}", "User")
    [Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1,.local", "User")

    Write-Status "Proxy enabled -> http://${proxyServer}"
    Write-Host "  HTTP_PROXY=http://${proxyServer}"
    Write-Host "  HTTPS_PROXY=http://${proxyServer}"
}

function Disable-Proxy {
    <#
    .SYNOPSIS
        Disable Windows system proxy.
    #>

    # Remove system proxy settings
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -Type DWord | Out-Null

    # Force Windows to apply registry changes immediately
    [WinInet]::RefreshProxy()

    # Clear environment variables
    Remove-Item Env:\HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue

    [Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")

    Write-Status "Proxy disabled"
}

function Show-Status {
    <#
    .SYNOPSIS
        Display current proxy configuration and connectivity.
    #>

    # System proxy registry check
    $proxyEnabled = (Get-ItemProperty -Path $regPath -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    Write-Host "System proxy : $(if ($proxyEnabled -eq 1) { 'ON' } else { 'OFF' })"

    if ($proxyEnabled -eq 1) {
        $server = (Get-ItemProperty -Path $regPath -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
        Write-Host "Proxy server : $server"
    }

    # Environment variables
    Write-Host ""
    Write-Host "HTTP_PROXY (process) : $($env:HTTP_PROXY)"
    Write-Host "HTTP_PROXY (user)    : $([Environment]::GetEnvironmentVariable('HTTP_PROXY', 'User'))"
    Write-Host "HTTPS_PROXY (user)   : $([Environment]::GetEnvironmentVariable('HTTPS_PROXY', 'User'))"

    # Port connectivity test
    Write-Host ""
    Write-Host "Port ${proxyPort} check:"
    try {
        $conn = [System.Net.Sockets.TcpClient]::new()
        $task = $conn.ConnectAsync($proxyHost, $proxyPort)
        if ($task.Wait(2000) -and $conn.Connected) {
            Write-Host "  ${proxyHost}:${proxyPort} - Connected (proxy running)" -ForegroundColor Green
            $conn.Close()
        }
        else {
            Write-Host "  ${proxyHost}:${proxyPort} - Not reachable (proxy not running?)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ${proxyHost}:${proxyPort} - Not reachable" -ForegroundColor Red
    }
}

function Test-Proxy {
    <#
    .SYNOPSIS
        Test if proxy is working by accessing google.com.
    #>

    Write-Status "Testing proxy connection..."
    try {
        $result = Invoke-WebRequest -Uri "https://www.google.com" -Proxy "http://${proxyServer}" -TimeoutSec 10 -UseBasicParsing
        Write-Host "SUCCESS! Google reachable (HTTP $($result.StatusCode))" -ForegroundColor Green
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Make sure Clash/Mihomo is running on ${proxyServer}"
    }
}

# ============================================================================
# MAIN
# ============================================================================

switch ($Action) {
    "enable"  { Enable-Proxy }
    "disable" { Disable-Proxy }
    "status"  { Show-Status }
    "test"    { Test-Proxy }
}
