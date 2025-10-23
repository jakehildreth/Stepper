function Reset-StepperState {
    <#
    .SYNOPSIS
        Clears all saved stepper state.
    
    .DESCRIPTION
        Removes the saved state file, effectively resetting the stepper
        to allow starting fresh. Prompts for confirmation before removing.
        
        Supports -WhatIf and -Confirm parameters.
    
    .EXAMPLE
        Reset-StepperState
        
        Prompts for confirmation then clears the state.
    
    .EXAMPLE
        Reset-StepperState -Confirm:$false
        
        Clears the state without prompting.
    
    .EXAMPLE
        Reset-StepperState -WhatIf
        
        Shows what would happen without actually clearing state.
    
    .NOTES
        This action cannot be undone. All stepper progress will be lost.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()
    
    Show-StepperHeader
    
    $statePath = Get-StateFilePath
    
    if (Test-Path $statePath) {
        if ($PSCmdlet.ShouldProcess($statePath, "Remove stepper state file and reset all progress")) {
            Clear-StepperState -Confirm:$false
            Write-Host "`nstepper state has been reset." -ForegroundColor Green
            Write-Host "Run 'Start-Stepper' to begin a new stepper." -ForegroundColor Cyan
        }
    } else {
        Write-Host "No saved stepper state found." -ForegroundColor Yellow
        Write-Host "Nothing to reset." -ForegroundColor Gray
    }
}
