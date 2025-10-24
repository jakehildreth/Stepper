function Show-StepperProgress {
    <#
    .SYNOPSIS
        Displays current progress summary.
    
    .DESCRIPTION
        Shows a formatted summary of the Stepper progress including:
        - Stepper ID
        - Start and update timestamps
        - Current status
        - Completed steps with durations
        - Overall percentage complete
    
    .PARAMETER State
        The Stepper state hashtable containing progress information.
    
    .PARAMETER TotalSteps
        The total number of steps in the Stepper.
    
    .EXAMPLE
        Show-StepperProgress -State $state -TotalSteps 5
        
        Displays progress for a 5-step Stepper.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalSteps
    )
    
    $completed = $State.CompletedSteps.Count
    $percentComplete = if ($TotalSteps -gt 0) { 
        [math]::Round(($completed / $TotalSteps) * 100, 1) 
    } else { 
        0 
    }
    
    Write-Host "`nProgress Summary:" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 50)) -ForegroundColor Gray
    Write-Host "  Stepper ID    : $($State.StepperId)" -ForegroundColor Gray
    Write-Host "  Started At       : $($State.StartedAt)" -ForegroundColor Gray
    Write-Host "  Last Updated     : $($State.LastUpdated)" -ForegroundColor Gray
    Write-Host "  Status           : $($State.Status)" -ForegroundColor $(
        if ($State.Status -eq 'Completed') { 'Green' } 
        elseif ($State.Status -eq 'Failed') { 'Red' } 
        else { 'Yellow' }
    )
    Write-Host "  Completed Steps  : $completed / $TotalSteps ($percentComplete%)" -ForegroundColor Gray
    Write-Host ("  " + ("-" * 50)) -ForegroundColor Gray
    
    if ($State.CompletedSteps.Count -gt 0) {
        Write-Host "`nCompleted Steps:" -ForegroundColor Green
        $State.CompletedSteps | ForEach-Object {
            $stepResult = $State.StepResults[$_]
            $duration = if ($stepResult.Duration) { " ($($stepResult.Duration))" } else { "" }
            Write-Host "  ✓ $_$duration" -ForegroundColor Green
        }
    }
    
    Write-Host ""
}
