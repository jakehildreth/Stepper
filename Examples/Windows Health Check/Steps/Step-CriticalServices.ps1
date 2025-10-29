# Step 4: Critical Services Check
<#
.SYNOPSIS
    Verifies that critical Windows services are running.

.DESCRIPTION
    Checks the status of essential Windows services and reports any that are stopped.
    This step receives all results from previous steps via $AllData parameter.
    Returns $true on success, $false on failure.
#>

param(
    [Parameter(Mandatory = $false)]
    [array]$AllData
)

Write-Host "`n--- Critical Services Check ---" -ForegroundColor Yellow

# Define critical services to check
$criticalServices = @(
    'Winmgmt',      # Windows Management Instrumentation
    'wuauserv',     # Windows Update
    'BITS',         # Background Intelligent Transfer Service
    'EventLog',     # Windows Event Log
    'PlugPlay',     # Plug and Play
    'RpcSs',        # Remote Procedure Call (RPC)
    'LanmanServer', # Server (for file sharing)
    'LanmanWorkstation', # Workstation (for network access)
    'Dhcp',         # DHCP Client
    'Dnscache',     # DNS Client
    'mpssvc'        # Windows Defender Firewall
)

try {
    Write-Host "`nChecking Critical Services:" -ForegroundColor Cyan
    
    $stoppedServices = @()
    $runningServices = @()
    
    foreach ($serviceName in $criticalServices) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            
            if ($service.Status -eq 'Running') {
                Write-Host "  ✓ $($service.DisplayName)" -ForegroundColor Green -NoNewline
                Write-Host " - Running" -ForegroundColor Gray
                $runningServices += $service.Name
            } else {
                Write-Host "  ❌ $($service.DisplayName)" -ForegroundColor Red -NoNewline
                Write-Host " - $($service.Status)" -ForegroundColor Red
                $stoppedServices += @{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    Status = $service.Status.ToString()
                }
            }
        } catch {
            Write-Host "  ⚠️  $serviceName - Not found or access denied" -ForegroundColor Yellow
        }
    }
    
    # Summary
    Write-Host "`nService Check Summary:" -ForegroundColor Cyan
    Write-Host "  Running Services : $($runningServices.Count)" -ForegroundColor Green
    
    if ($stoppedServices.Count -gt 0) {
        Write-Host "  Stopped Services : $($stoppedServices.Count)" -ForegroundColor Red
        Write-Host "`n  ⚠️  WARNING: Some critical services are not running!" -ForegroundColor Yellow
        Write-Host "  This may affect system functionality." -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ All critical services are running normally" -ForegroundColor Green
    }
    
    # Store results
    if (-not $global:HealthCheckResults) {
        $global:HealthCheckResults = @{}
    }
    $global:HealthCheckResults.Services = @{
        TotalChecked = $criticalServices.Count
        Running = $runningServices.Count
        Stopped = $stoppedServices
    }
    
    # Generate final summary report
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "HEALTH CHECK COMPLETE - SUMMARY REPORT" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    
    # Use results from all previous steps if available
    if ($global:HealthCheckResults) {
        Write-Host "`nSystem Overview:" -ForegroundColor White
        
        if ($global:HealthCheckResults.SystemInfo) {
            Write-Host "  Computer      : $($global:HealthCheckResults.SystemInfo.ComputerName)" -ForegroundColor Gray
            Write-Host "  Uptime        : $($global:HealthCheckResults.SystemInfo.UptimeDays) days" -ForegroundColor Gray
            Write-Host "  Total RAM     : $($global:HealthCheckResults.SystemInfo.TotalRAM_GB) GB" -ForegroundColor Gray
        }
        
        Write-Host "`nIssues Found:" -ForegroundColor White
        $issueCount = 0
        
        if ($global:HealthCheckResults.DiskSpace) {
            if ($global:HealthCheckResults.DiskSpace.CriticalDisks.Count -gt 0) {
                Write-Host "  ❌ CRITICAL: Low disk space on $($global:HealthCheckResults.DiskSpace.CriticalDisks -join ', ')" -ForegroundColor Red
                $issueCount++
            }
            if ($global:HealthCheckResults.DiskSpace.WarningDisks.Count -gt 0) {
                Write-Host "  ⚠️  WARNING: Disk space running low on $($global:HealthCheckResults.DiskSpace.WarningDisks -join ', ')" -ForegroundColor Yellow
                $issueCount++
            }
        }
        
        if ($global:HealthCheckResults.WindowsUpdate) {
            if ($global:HealthCheckResults.WindowsUpdate.PendingUpdateCount -gt 0) {
                Write-Host "  ⚠️  WARNING: $($global:HealthCheckResults.WindowsUpdate.PendingUpdateCount) pending Windows updates" -ForegroundColor Yellow
                $issueCount++
            }
        }
        
        if ($stoppedServices.Count -gt 0) {
            Write-Host "  ❌ CRITICAL: $($stoppedServices.Count) critical services not running" -ForegroundColor Red
            $issueCount++
        }
        
        if ($issueCount -eq 0) {
            Write-Host "  ✓ No issues found - System is healthy!" -ForegroundColor Green
        }
        
        Write-Host "`nOverall Status: " -NoNewline -ForegroundColor White
        if ($issueCount -eq 0) {
            Write-Host "HEALTHY ✓" -ForegroundColor Green
        } elseif ($issueCount -le 2) {
            Write-Host "NEEDS ATTENTION ⚠️" -ForegroundColor Yellow
        } else {
            Write-Host "CRITICAL ❌" -ForegroundColor Red
        }
    }
    
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    
    return $true
} catch {
    Write-Error "Failed to check critical services: $_"
    return $false
}
