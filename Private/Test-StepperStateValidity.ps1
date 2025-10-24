function Test-StepperStateValidity {
    <#
    .SYNOPSIS
        Validates if the saved state is still relevant.
    
    .DESCRIPTION
        Checks the Stepper state for validity by verifying:
        - Version compatibility
        - Age of the state (default max 7 days)
        - Valid timestamp format
    
    .PARAMETER State
        The Stepper state hashtable to validate.
    
    .PARAMETER MaxAgeDays
        Maximum age in days before state is considered stale.
        Default is 7 days.
    
    .OUTPUTS
        System.Boolean - $true if state is valid, $false otherwise.
    
    .EXAMPLE
        if (Test-StepperStateValidity -State $state) {
            # State is valid, proceed
        }
        
        Validates state with default 7-day age limit.
    
    .EXAMPLE
        if (Test-StepperStateValidity -State $state -MaxAgeDays 30) {
            # State is valid, proceed
        }
        
        Validates state with custom 30-day age limit.
    
    .NOTES
        Displays warnings if state is invalid.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxAgeDays = 7
    )
    
    # Check version compatibility
    if ($State.Version -ne '1.0.0') {
        Write-Warning "State file version mismatch. Expected 1.0.0, found $($State.Version)"
        return $false
    }
    
    # Check age
    if ($State.LastUpdated) {
        try {
            $lastUpdate = [DateTime]::Parse($State.LastUpdated)
            $age = (Get-Date) - $lastUpdate
            
            if ($age.TotalDays -gt $MaxAgeDays) {
                Write-Warning "State is $([math]::Round($age.TotalDays, 1)) days old (max: $MaxAgeDays days)"
                return $false
            }
            
            Write-Verbose "State age: $([math]::Round($age.TotalDays, 1)) days (valid)"
        } catch {
            Write-Warning "Invalid LastUpdated timestamp in state: $($State.LastUpdated)"
            return $false
        }
    } else {
        Write-Warning "State missing LastUpdated timestamp"
        return $false
    }
    
    Write-Verbose "State validation passed"
    return $true
}
