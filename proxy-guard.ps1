<#
.SYNOPSIS
    Proxy Guard - Auto-cleanup proxy settings when proxy software exits.
.DESCRIPTION
    Monitors FlClash/Clash/Mihomo processes. When all proxy software exits,
    automatically disables system proxy to prevent "no internet" situations.

    Solves the common problem: close proxy GUI → proxy port dies →
    system proxy still points to dead port → can't browse the internet.

.EXAMPLE
    .\proxy-guard.ps1       # Start monitoring (wait for proxy to exit)
    .\proxy-guard.ps1 watch # Same as above, continuous monitoring
    .\proxy-guard.ps1 now   # Force cleanup right now
    .\proxy-guard.ps1 status # Check what proxy processes are running
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet("watch", "now", "status")]
    [string]$Action = "watch"
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$proxyScript = Join-Path $scriptDir "proxy.ps1"

# Known proxy process names (case-insensitive partial match)
$proxyProcessNames = @(
    "FlClashCore",
    "mihomo",
    "mihomo-windows",
    "Clash",
    "clash-verge",
    "ClashVerge"
)

$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"

# ============================================================================
# WININET REFRESH (same as proxy.ps1)
# ============================================================================
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

function Write-Guard {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[Guard] $Message" -ForegroundColor $Color
}

function Get-ProxyProcesses {
    <#
    .SYNOPSIS
        Find all known proxy software processes currently running.
    #>
    $found = @()
    foreach ($name in $proxyProcessNames) {
        try {
            $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
            foreach ($p in $procs) {
                $found += [PSCustomObject]@{
                    Id          = $p.Id
                    Name        = $p.ProcessName
                    StartTime   = $p.StartTime
                }
            }
        }
        catch {}
    }
    return $found
}

function Get-ProxyPIDs {
    <#
    .SYNOPSIS
        Get list of known proxy process IDs.
    #>
    $pids = @()
    foreach ($name in $proxyProcessNames) {
        try {
            $pids += (Get-Process -Name $name -ErrorAction SilentlyContinue).Id
        }
        catch {}
    }
    return $pids | Sort-Object -Unique
}

function Is-SystemProxyEnabled {
    $val = (Get-ItemProperty -Path $regPath -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    return ($val -eq 1)
}

function Cleanup-Proxy {
    <#
    .SYNOPSIS
        Force cleanup all proxy settings — registry + environment variables.
    #>
    Write-Guard "Cleaning up proxy settings..." "Yellow"

    # Registry
    Set-ItemProperty -Path $regPath -Name ProxyEnable -Value 0 -Type DWord | Out-Null
    [WinInet]::RefreshProxy()

    # Environment variables
    Remove-Item Env:\HTTP_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
    [Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")

    Write-Guard "Proxy settings cleaned. You can now browse normally!" "Green"
}

function Show-Status {
    $procs = Get-ProxyProcesses
    Write-Guard "Known proxy processes:"
    if ($procs.Count -eq 0) {
        Write-Host "  None running"
    }
    else {
        $procs | Format-Table Id, Name, StartTime -AutoSize
    }

    Write-Host ""
    Write-Guard "System proxy: $(if (Is-SystemProxyEnabled) { 'ON' } else { 'OFF' })"
    $server = (Get-ItemProperty -Path $regPath -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
    if ($server) {
        Write-Host "  ProxyServer: $server"
    }
}

# ============================================================================
# MAIN
# ============================================================================

switch ($Action) {
    "now" {
        Cleanup-Proxy
    }

    "status" {
        Show-Status
    }

    "watch" {
        # Find initial proxy processes
        $pids = Get-ProxyPIDs
        if ($pids.Count -eq 0) {
            Write-Guard "No proxy software detected. If proxy is stuck, run: proxy-guard.ps1 now" "Yellow"
            if (Is-SystemProxyEnabled) {
                Write-Guard "WARNING: System proxy is ON but no proxy process running! This causes no-internet!"
                Cleanup-Proxy
            }
            exit 0
        }

        Write-Guard "Monitoring $(($pids -join ', ')) ($($pids.Count) process(es))"
        Write-Guard "Will auto-cleanup proxy when all are gone. Press Ctrl+C to stop."
        Write-Host ""

        # Main monitoring loop
        $wasEnabled = $false
        while ($true) {
            $alive = @()
            foreach ($pid in $pids) {
                try {
                    $null = Get-Process -Id $pid -ErrorAction Stop
                    $alive += $pid
                }
                catch {}
            }

            if ($alive.Count -eq 0) {
                # All proxy processes exited
                Write-Host ""
                Write-Guard "All proxy processes have exited!" "Yellow"

                # Check if system proxy is still ON
                if (Is-SystemProxyEnabled) {
                    $wasEnabled = $true
                    Write-Guard "System proxy was left ON with no proxy running — cleaning up..." "Yellow"
                    Cleanup-Proxy
                }
                else {
                    Write-Guard "System proxy is already OFF, no cleanup needed." "Green"
                }

                Write-Guard "Guard exiting. Safe browsing!" "Green"
                break
            }
            elseif ($alive.Count -ne $pids.Count) {
                # Some died, update tracking
                $pids = $alive
                Write-Guard "Proxy process(es) remaining: $(($pids -join ', '))"
            }

            Start-Sleep -Seconds 2
        }
    }
}
