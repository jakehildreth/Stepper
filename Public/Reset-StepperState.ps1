function Reset-StepperState {
    <#
    .SYNOPSIS
        Clears all saved Stepper state.
    
    .DESCRIPTION
        Removes the saved state file, effectively resetting the Stepper
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
        This action cannot be undone. All Stepper progress will be lost.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()
    
    Show-StepperHeader
    
    $statePath = Get-StateFilePath
    
    if (Test-Path $statePath) {
        if ($PSCmdlet.ShouldProcess($statePath, "Remove Stepper state file and reset all progress")) {
            Clear-StepperState -Confirm:$false
            Write-Host "`nStepper state has been reset." -ForegroundColor Green
            Write-Host "Run 'Start-Stepper' to begin a new Stepper." -ForegroundColor Cyan
        }
    } else {
        Write-Host "No saved Stepper state found." -ForegroundColor Yellow
        Write-Host "Nothing to reset." -ForegroundColor Gray
    }
}
