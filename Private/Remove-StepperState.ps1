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
    
    if (Test-Path -Path $StatePath) {
        try {
            Remove-Item -Path $StatePath -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to remove state file '$StatePath': $_"
        }
    }
}
