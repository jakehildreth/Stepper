function Show-StepperStatus {
    <#
    .SYNOPSIS
        Displays the current stepper progress without running any steps.
    
    .DESCRIPTION
        Shows the progress summary of the current or last stepper including
        completed steps, current status, and overall progress percentage.
        
        Useful for checking on stepper status without starting or resuming.
    
    .EXAMPLE
        Show-StepperStatus
        
        Displays current stepper progress.
    
    .NOTES
        If no stepper state exists, indicates that no stepper has been started.
    #>
    [CmdletBinding()]
    param()
    
    Show-StepperHeader
    
    $state = Get-StepperState
    $steps = Get-StepperSteps
    
    if ($state.CompletedSteps.Count -eq 0 -and $state.Status -eq 'InProgress' -and 
        [DateTime]::Parse($state.StartedAt) -gt (Get-Date).AddMinutes(-1)) {
        # This is a brand new state that was just created
        Write-Host "No stepper progress found." -ForegroundColor Yellow
        Write-Host "Run 'Start-Stepper' to begin a new stepper." -ForegroundColor Gray
    } else {
        Show-StepperProgress -State $state -TotalSteps $steps.Count
        
        if ($state.Status -eq 'InProgress') {
            Write-Host "Run 'Start-Stepper -Resume' to continue the stepper." -ForegroundColor Cyan
        } elseif ($state.Status -eq 'Failed') {
            Write-Host "Run 'Start-Stepper -Resume' to retry from the failed step." -ForegroundColor Yellow
        } else {
            Write-Host "stepper is complete. Run 'Reset-StepperState' to start fresh." -ForegroundColor Green
        }
    }
}
