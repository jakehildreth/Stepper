# Step 1: System Information and Uptime Check
<#
.SYNOPSIS
    Collects basic system information and uptime.

.DESCRIPTION
    Gathers OS version, computer name, uptime, and basic hardware info.
    Returns $true on success, $false on failure.
#>

param()

Write-Host "`n--- System Information ---" -ForegroundColor Yellow

try {
    # Get computer info
    $computerInfo = Get-ComputerInfo -ErrorAction Stop
    
    # Display OS Information
    Write-Host "`nOperating System:" -ForegroundColor Cyan
    Write-Host "  Name          : $($computerInfo.OsName)" -ForegroundColor White
    Write-Host "  Version       : $($computerInfo.OsVersion)" -ForegroundColor White
    Write-Host "  Architecture  : $($computerInfo.OsArchitecture)" -ForegroundColor White
    Write-Host "  Install Date  : $($computerInfo.OsInstallDate)" -ForegroundColor White
    
    # Calculate uptime
    $lastBoot = $computerInfo.OsLastBootUpTime
    $uptime = (Get-Date) - $lastBoot
    $uptimeString = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    
    Write-Host "`nSystem Status:" -ForegroundColor Cyan
    Write-Host "  Computer Name : $($computerInfo.CsName)" -ForegroundColor White
    Write-Host "  Last Boot     : $lastBoot" -ForegroundColor White
    Write-Host "  Uptime        : $uptimeString" -ForegroundColor White
    
    # Hardware info
    Write-Host "`nHardware:" -ForegroundColor Cyan
    Write-Host "  Processor     : $($computerInfo.CsProcessors[0].Name)" -ForegroundColor White
    Write-Host "  Total RAM     : $([math]::Round($computerInfo.CsTotalPhysicalMemory / 1GB, 2)) GB" -ForegroundColor White
    
    # Check if uptime is excessive (suggest reboot if > 30 days)
    if ($uptime.Days -gt 30) {
        Write-Host "`n  ⚠️  WARNING: System has been running for over 30 days. Consider rebooting." -ForegroundColor Yellow
    } else {
        Write-Host "`n  ✓ System uptime is healthy" -ForegroundColor Green
    }
    
    # Store results for potential use by other steps
    $global:HealthCheckResults = @{
        SystemInfo = @{
            ComputerName = $computerInfo.CsName
            OSVersion = $computerInfo.OsVersion
            UptimeDays = $uptime.Days
            TotalRAM_GB = [math]::Round($computerInfo.CsTotalPhysicalMemory / 1GB, 2)
            LastBoot = $lastBoot
        }
    }
    
    Write-Host ""
    return $true
} catch {
    Write-Error "Failed to collect system information: $_"
    return $false
}
