function New-StepperState {
    <#
    .SYNOPSIS
        Creates a new empty stepper state object.
    
    .DESCRIPTION
        Initializes a new hashtable containing the default structure for
        tracking stepper progress, including metadata about the environment.
    
    .OUTPUTS
        System.Collections.Hashtable - A new stepper state object.
    
    .EXAMPLE
        $state = New-StepperState
        
        Creates a new stepper state with default values.
    
    .NOTES
        The state object includes:
        - Version: State file format version
        - StepperId: Unique identifier for this stepper run
        - StartedAt: Timestamp when stepper started
        - LastUpdated: Timestamp of last state update
        - CompletedSteps: Array of completed step names
        - CurrentStepIndex: Index of current/next step
        - Status: Current status (InProgress, Completed, Failed)
        - StepResults: Hashtable of results per step
        - Metadata: Environment information
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    
    Write-Verbose "Creating new stepper state"
    
    return @{
        Version = '1.0.0'
        StepperId = [guid]::NewGuid().ToString()
        StartedAt = Get-Date -Format 'o'
        LastUpdated = Get-Date -Format 'o'
        CompletedSteps = @()
        CurrentStepIndex = 0
        Status = 'InProgress'
        StepResults = @{}
        Metadata = @{
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            PSVersion = $PSVersionTable.PSVersion.ToString()
            Domain = $env:USERDNSDOMAIN
        }
    }
}
