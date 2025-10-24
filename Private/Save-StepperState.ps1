function Save-StepperState {
    <#
    .SYNOPSIS
        Saves the Stepper state to a JSON file.
    
    .DESCRIPTION
        Serializes the Stepper state hashtable to JSON format and saves
        it to disk. Updates the LastUpdated timestamp automatically.
    
    .PARAMETER State
        The Stepper state hashtable to save.
    
    .PARAMETER Path
        The path where the state file should be saved. If not specified,
        uses the default path from Get-StateFilePath.
    
    .EXAMPLE
        Save-StepperState -State $state
        
        Saves the state to the default location.
    
    .EXAMPLE
        Save-StepperState -State $state -Path 'C:\Temp\my-state.json'
        
        Saves the state to a custom location.
    
    .NOTES
        The state is saved with indentation for readability.
        Throws an error if save fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-StateFilePath)
    )
    
    try {
        # Update timestamp
        $State.LastUpdated = Get-Date -Format 'o'
        
        Write-Verbose "Saving state to: $Path"
        
        # Convert to JSON with good depth for nested objects
        $json = $State | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Save to file
        $json | Set-Content -Path $Path -Force -Encoding UTF8
        
        Write-Verbose "State saved successfully"
        Write-Debug "State content: $json"
    } catch {
        Write-Error "Failed to save state to '$Path': $_"
        throw
    }
}
