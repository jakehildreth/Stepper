<#
.SYNOPSIS
    DataFlow-Demo Stepper script.

.DESCRIPTION
    Multi-step Stepper script using the Stepper module.
    State is automatically saved and can be resumed if interrupted.
    Demonstrates passing initial data to all steps.

.PARAMETER UserName
    Name of the user running the health check. This will be passed to all steps
    and used in the final report.

.PARAMETER Fresh
    Start fresh, ignoring any saved state.

.PARAMETER ShowStatus
    Display current progress without running steps.

.PARAMETER Reset
    Reset all saved progress.

.EXAMPLE
    .\DataFlow-Demo.ps1 -UserName "Alice"
    
    Run the Stepper with user name (resumes automatically if interrupted).

.EXAMPLE
    .\DataFlow-Demo.ps1 -UserName "Bob" -Fresh
    
    Start fresh with a specific user name, ignoring any saved state.

.NOTES
    Requires: Stepper module
    Configuration: DataFlow-Demo.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserName = $env:USER,
    
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
    # Create initial data to pass to all steps
    $initialData = @{
        UserName = $UserName
        StartTime = Get-Date
    }
    
    if ($Fresh) {
        Start-Stepper -Fresh -InitialData $initialData
    } else {
        Start-Stepper -InitialData $initialData
    }
    
    # Start-Stepper displays its own completion message when fully complete
    # No need to display additional message here
} catch {
    Write-Error "Stepper failed: $_"
    return
}
