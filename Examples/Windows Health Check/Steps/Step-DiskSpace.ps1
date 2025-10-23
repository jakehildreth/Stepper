# Step 2: Disk Space Analysis
<#
.SYNOPSIS
    Analyzes disk space usage on all local drives.

.DESCRIPTION
    Checks free space on all fixed drives and warns if any are below 10% free.
    Returns $true on success, $false on failure.
#>

param()

Write-Host "`n--- Disk Space Analysis ---" -ForegroundColor Yellow

try {
    # Get all fixed disks
    $disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }
    
    if ($disks.Count -eq 0) {
        Write-Warning "No fixed disks found"
        return $false
    }
    
    Write-Host "`nDisk Space Status:" -ForegroundColor Cyan
    
    $criticalDisks = @()
    $warningDisks = @()
    
    foreach ($disk in $disks) {
        $totalSize = $disk.Used + $disk.Free
        $freePercent = [math]::Round(($disk.Free / $totalSize) * 100, 2)
        $freeGB = [math]::Round($disk.Free / 1GB, 2)
        $totalGB = [math]::Round($totalSize / 1GB, 2)
        
        Write-Host "`n  Drive $($disk.Name):\" -ForegroundColor White
        Write-Host "    Total Space : $totalGB GB" -ForegroundColor Gray
        Write-Host "    Free Space  : $freeGB GB ($freePercent%)" -ForegroundColor Gray
        
        # Determine status
        if ($freePercent -lt 10) {
            Write-Host "    Status      : ❌ CRITICAL - Less than 10% free" -ForegroundColor Red
            $criticalDisks += "$($disk.Name):\"
        } elseif ($freePercent -lt 20) {
            Write-Host "    Status      : ⚠️  WARNING - Less than 20% free" -ForegroundColor Yellow
            $warningDisks += "$($disk.Name):\"
        } else {
            Write-Host "    Status      : ✓ Healthy" -ForegroundColor Green
        }
    }
    
    # Summary
    Write-Host "`nDisk Space Summary:" -ForegroundColor Cyan
    if ($criticalDisks.Count -gt 0) {
        Write-Host "  Critical drives: $($criticalDisks -join ', ')" -ForegroundColor Red
        Write-Host "  ACTION REQUIRED: Free up disk space immediately!" -ForegroundColor Red
    } elseif ($warningDisks.Count -gt 0) {
        Write-Host "  Warning drives: $($warningDisks -join ', ')" -ForegroundColor Yellow
        Write-Host "  RECOMMENDED: Consider cleaning up disk space soon" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ All drives have adequate free space" -ForegroundColor Green
    }
    
    # Store results
    if (-not $global:HealthCheckResults) {
        $global:HealthCheckResults = @{}
    }
    $global:HealthCheckResults.DiskSpace = @{
        CriticalDisks = $criticalDisks
        WarningDisks = $warningDisks
        TotalDisks = $disks.Count
    }
    
    Write-Host ""
    return $true
} catch {
    Write-Error "Failed to analyze disk space: $_"
    return $false
}
