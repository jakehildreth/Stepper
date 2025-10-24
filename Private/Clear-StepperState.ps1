function Clear-StepperState {
    <#
    .SYNOPSIS
        Removes the saved state file.
    
    .DESCRIPTION
        Deletes the Stepper state file from disk, effectively resetting
        all progress. Supports -WhatIf and -Confirm for safety.
    
    .PARAMETER Path
        The path to the state file to remove. If not specified, uses the
        default path from Get-StateFilePath.
    
    .EXAMPLE
        Clear-StepperState
        
        Removes the default state file.
    
    .EXAMPLE
        Clear-StepperState -WhatIf
        
        Shows what would happen without actually removing the file.
    
    .EXAMPLE
        Clear-StepperState -Path 'C:\Temp\my-state.json'
        
        Removes a custom state file.
    
    .NOTES
        If the file doesn't exist, a warning is displayed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-StateFilePath)
    )
    
    if (Test-Path $Path) {
        if ($PSCmdlet.ShouldProcess($Path, "Remove Stepper state file")) {
            try {
                Remove-Item -Path $Path -Force -ErrorAction Stop
                Write-Host "State file removed: $Path" -ForegroundColor Green
                Write-Verbose "State successfully cleared"
            } catch {
                Write-Error "Failed to remove state file '$Path': $_"
            }
        }
    } else {
        Write-Warning "No state file found at: $Path"
    }
}
