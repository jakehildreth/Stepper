function Remove-StepperState {
    <#
    .SYNOPSIS
        Removes the Stepper state file.
    
    .DESCRIPTION
        Deletes the state file if it exists.
        Used when starting fresh or when the script completes successfully.
    
    .PARAMETER StatePath
        The path to the state file.
    
    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )
    
    # Only attempt removal if the file exists
    # Avoids unnecessary errors when state file was already cleaned up
    if (Test-Path -Path $StatePath) {
        try {
            # -Force ensures removal even if file is read-only
            # Used when script completes successfully or user chooses to start fresh
            Remove-Item -Path $StatePath -Force -ErrorAction Stop
        }
        catch {
            # Warn but don't fail - inability to remove state isn't critical
            # User can manually delete the .stepper file if needed
            Write-Warning "Failed to remove state file '$StatePath': $_"
        }
    }
}
