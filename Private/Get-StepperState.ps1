function Get-StepperState {
    <#
    .SYNOPSIS
        Loads the Stepper state from file, or creates a new one.
    
    .DESCRIPTION
        Attempts to load a saved Stepper state from disk. If the file
        doesn't exist or can't be loaded, returns a new empty state.
        
        Converts the JSON PSCustomObject back to a hashtable for easier
        manipulation in PowerShell.
    
    .PARAMETER Path
        The path to the state file. If not specified, uses the default
        path from Get-StateFilePath.
    
    .OUTPUTS
        System.Collections.Hashtable - The loaded or new Stepper state.
    
    .EXAMPLE
        $state = Get-StepperState
        
        Loads the state from the default location or creates new.
    
    .EXAMPLE
        $state = Get-StepperState -Path 'C:\Temp\my-state.json'
        
        Loads the state from a custom location.
    
    .NOTES
        If loading fails, warnings are displayed and a new state is returned.
        This ensures the Stepper can always proceed.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-StateFilePath)
    )
    
    if (Test-Path $Path) {
        try {
            Write-Verbose "Loading state from: $Path"
            
            $json = Get-Content -Path $Path -Raw -Encoding UTF8
            $stateObject = $json | ConvertFrom-Json
            
            # Convert PSCustomObject back to hashtable for easier manipulation
            $state = @{
                Version = $stateObject.Version
                StepperId = $stateObject.StepperId
                StartedAt = $stateObject.StartedAt
                LastUpdated = $stateObject.LastUpdated
                CompletedSteps = @($stateObject.CompletedSteps)
                CurrentStepIndex = $stateObject.CurrentStepIndex
                Status = $stateObject.Status
                StepResults = @{}
                Metadata = @{}
            }
            
            # Convert nested objects
            if ($stateObject.StepResults) {
                $stateObject.StepResults.PSObject.Properties | ForEach-Object {
                    $state.StepResults[$_.Name] = $_.Value
                }
            }
            
            if ($stateObject.Metadata) {
                $stateObject.Metadata.PSObject.Properties | ForEach-Object {
                    $state.Metadata[$_.Name] = $_.Value
                }
            }
            
            Write-Verbose "State loaded successfully (ID: $($state.StepperId))"
            return $state
        } catch {
            Write-Warning "Failed to load state file: $_"
            Write-Warning "Starting with fresh state..."
            return New-StepperState
        }
    } else {
        Write-Verbose "No existing state file found, creating new state"
        return New-StepperState
    }
}
