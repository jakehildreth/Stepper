# Step 3: Windows Update Status Check
<#
.SYNOPSIS
    Checks the status of Windows Update.

.DESCRIPTION
    Verifies Windows Update service is running and checks for pending updates.
    Returns $true on success, $false on failure.
#>

param()

Write-Host "`n--- Windows Update Status ---" -ForegroundColor Yellow

try {
    # Check Windows Update service
    Write-Host "`nWindows Update Service:" -ForegroundColor Cyan
    $wuService = Get-Service -Name wuauserv -ErrorAction Stop
    
    Write-Host "  Service Name  : $($wuService.DisplayName)" -ForegroundColor Gray
    Write-Host "  Status        : $($wuService.Status)" -ForegroundColor $(if ($wuService.Status -eq 'Running') { 'Green' } else { 'Yellow' })
    Write-Host "  Startup Type  : $($wuService.StartType)" -ForegroundColor Gray
    
    if ($wuService.Status -ne 'Running') {
        Write-Host "  ⚠️  Note: Service is not running (this is normal when not checking for updates)" -ForegroundColor Yellow
    }
    
    # Check for pending updates using COM object
    Write-Host "`nChecking for Pending Updates..." -ForegroundColor Cyan
    
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        # Search for updates that are not installed
        Write-Host "  Searching... (this may take a moment)" -ForegroundColor Gray
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        
        $updateCount = $searchResult.Updates.Count
        
        if ($updateCount -eq 0) {
            Write-Host "  ✓ No pending updates found" -ForegroundColor Green
            $pendingUpdates = @()
        } else {
            Write-Host "  ⚠️  Found $updateCount pending update(s)" -ForegroundColor Yellow
            Write-Host "`n  Pending Updates:" -ForegroundColor Cyan
            
            $pendingUpdates = @()
            foreach ($update in $searchResult.Updates) {
                $importance = if ($update.AutoSelectOnWebSites) { "Important" } else { "Optional" }
                Write-Host "    - $($update.Title)" -ForegroundColor White
                Write-Host "      Category: $importance" -ForegroundColor Gray
                $pendingUpdates += $update.Title
            }
            
            Write-Host "`n  RECOMMENDATION: Install pending updates to keep system secure" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Could not check for pending updates: $_"
        Write-Host "  Note: This may require administrator privileges" -ForegroundColor Gray
        $updateCount = $null
        $pendingUpdates = @()
    }
    
    # Check last update installation time
    Write-Host "`nLast Update Installation:" -ForegroundColor Cyan
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $historyCount = $searcher.GetTotalHistoryCount()
        
        if ($historyCount -gt 0) {
            $history = $searcher.QueryHistory(0, 1) | Select-Object -First 1
            $lastUpdate = $history.Date
            Write-Host "  Last Update   : $lastUpdate" -ForegroundColor White
            
            $daysSinceUpdate = ((Get-Date) - $lastUpdate).Days
            if ($daysSinceUpdate -gt 30) {
                Write-Host "  ⚠️  WARNING: No updates in $daysSinceUpdate days" -ForegroundColor Yellow
            } else {
                Write-Host "  ✓ Recent update history ($daysSinceUpdate days ago)" -ForegroundColor Green
            }
        } else {
            Write-Host "  No update history available" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Could not retrieve update history" -ForegroundColor Gray
    }
    
    # Store results
    if (-not $global:HealthCheckResults) {
        $global:HealthCheckResults = @{}
    }
    $global:HealthCheckResults.WindowsUpdate = @{
        ServiceStatus = $wuService.Status.ToString()
        PendingUpdateCount = $updateCount
        PendingUpdates = $pendingUpdates
    }
    
    Write-Host ""
    return $true
} catch {
    Write-Error "Failed to check Windows Update status: $_"
    return $false
}
