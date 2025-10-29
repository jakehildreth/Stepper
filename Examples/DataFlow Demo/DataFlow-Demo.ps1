<#
.SYNOPSIS
    DataFlow-Demo Stepper script.

.DESCRIPTION
    Multi-step Stepper script using the Stepper module.
    State is automatically saved and can be resumed if interrupted.

.PARAMETER Fresh
    Start fresh, ignoring any saved state.

.PARAMETER ShowStatus
    Display current progress without running steps.

.PARAMETER Reset
    Reset all saved progress.

.EXAMPLE
    .\DataFlow-Demo.ps1
    
    Run the Stepper (resumes automatically if interrupted).

.EXAMPLE
    .\DataFlow-Demo.ps1 -Fresh
    
    Start fresh, ignoring any saved state.

.NOTES
    Requires: Stepper module
    Configuration: DataFlow-Demo.json
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

# Import Stepper module
if (-not (Get-Module -Name Stepper -ListAvailable)) {
    Write-Error "Stepper module is not installed. Install it with: Install-Module Stepper"
    return
}

Import-Module Stepper -Force

# Handle ShowStatus
if ($ShowStatus) {
    Show-StepperStatus
    return
}

# Handle Reset
if ($Reset) {
    Reset-StepperState
    return
}

# Note: Get-StepperSteps will automatically find DataFlow-Demo.json
# in the same directory as this script

# Run the Stepper using Stepper module
try {
    if ($Fresh) {
        Start-Stepper -Fresh
    } else {
        Start-Stepper
    }
    
    # Start-Stepper displays its own completion message when fully complete
    # No need to display additional message here
} catch {
    Write-Error "Stepper failed: $_"
    return
}
