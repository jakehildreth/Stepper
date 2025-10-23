#Requires -Modules Stepper

<#
.SYNOPSIS
    Windows Computer Health Check Script

.DESCRIPTION
    Runs a multi-step health check of a Windows computer including:
    - System information and uptime
    - Disk space analysis
    - Windows Update status
    - Critical service verification

.PARAMETER Fresh
    Start a completely fresh health check, ignoring any saved state.

.PARAMETER ShowStatus
    Display the current health check progress without running any steps.

.PARAMETER Reset
    Clear all saved progress and start fresh on next run.

.EXAMPLE
    .\Invoke-WindowsHealthCheck.ps1
    
    Runs the health check, resuming from last checkpoint if interrupted.

.EXAMPLE
    .\Invoke-WindowsHealthCheck.ps1 -Fresh
    
    Starts a completely fresh health check from the beginning.

.EXAMPLE
    .\Invoke-WindowsHealthCheck.ps1 -ShowStatus
    
    Shows current progress without running any checks.

.NOTES
    Author: Jake Hildreth
    Date: October 23, 2025
    Requires: Stepper module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Fresh,

    [Parameter(Mandatory = $false)]
    [switch]$ShowStatus,

    [Parameter(Mandatory = $false)]
    [switch]$Reset
)

# Handle different modes
if ($ShowStatus) {
    Show-StepperStatus
    return
}

if ($Reset) {
    Reset-StepperState
    Write-Host "Health check state has been reset." -ForegroundColor Green
    Write-Host "Run '.\Invoke-WindowsHealthCheck.ps1' to start a new check." -ForegroundColor Cyan
    return
}

# Display custom header
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                    ║" -ForegroundColor Cyan
Write-Host "║     Windows Computer Health Check Tool            ║" -ForegroundColor Cyan
Write-Host "║                                                    ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor Gray
Write-Host "User: $env:USERNAME" -ForegroundColor Gray
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Note: Get-StepperSteps will automatically find Invoke-WindowsHealthCheck.json
# in the same directory as this script

# Run the health check using Stepper
try {
    if ($Fresh) {
        Start-Stepper -Fresh
    } else {
        Start-Stepper
    }
} catch {
    Write-Error "Health check failed: $_"
    return
}

Write-Host ""
Write-Host "Health check complete! Review the results above." -ForegroundColor Green
Write-Host ""
