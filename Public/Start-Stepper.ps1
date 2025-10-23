function Start-Stepper {
    <#
    .SYNOPSIS
        Main function to run the multi-step stepper.
    
    .DESCRIPTION
        Orchestrates the execution of all stepper steps, manages state
        persistence, handles errors, and provides progress feedback.
        
        By default, resumes from the last saved state. Use -Fresh to start over.
    
    .PARAMETER Fresh
        Start a completely new stepper, ignoring any saved state.
    
    .PARAMETER ConfigPath
        Path to the stepper configuration JSON file. If not specified, attempts to find
        a JSON file with the same base name as the calling script (e.g., MyScript.ps1 -> MyScript.json).
        Falls back to stepper-config.json in the module root if no match is found.
    
    .EXAMPLE
        Start-Stepper
        
        Automatically finds a JSON config with the same name as the calling script.
        Resumes from the last checkpoint (default behavior).
    
    .EXAMPLE
        Start-Stepper -Fresh
        
        Starts a completely new stepper from the beginning.
    
    .EXAMPLE
        Start-Stepper -ConfigPath ".\my-steps.json"
        
        Uses a custom configuration file.
    
    .NOTES
        State is automatically saved after each step.
        The stepper can be safely interrupted and resumed later.
        Completed steps can be skipped or re-run interactively.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Fresh,
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )
    
    Show-StepperHeader
    
    # Get all stepper steps
    if ($ConfigPath) {
        $steps = Get-StepperSteps -ConfigPath $ConfigPath
    } else {
        $steps = Get-StepperSteps
    }
    $totalSteps = $steps.Count
    
    Write-Verbose "Total steps defined: $totalSteps"
    
    # Load or create state (default is to resume)
    $state = if ($Fresh) {
        # User explicitly wants to start fresh
        Write-Host "Starting fresh stepper (ignoring saved state)..." -ForegroundColor Cyan
        New-StepperState
    } else {
        # Default behavior: try to resume
        $existingState = Get-StepperState
        
        # Default behavior: try to resume
        $existingState = Get-StepperState
        
        if ($existingState.Status -eq 'Completed') {
            Write-Host "Previous stepper was completed." -ForegroundColor Yellow
            Write-Host "Do you want to start a new stepper? (Y/N): " -NoNewline -ForegroundColor Yellow
            $response = Read-Host
            
            if ($response -eq 'Y') {
                New-StepperState
            } else {
                Write-Host "Exiting..." -ForegroundColor Gray
                return
            }
        } elseif (-not (Test-StepperStateValidity -State $existingState)) {
            Write-Host "Saved state is invalid or too old." -ForegroundColor Yellow
            Write-Host "Do you want to start fresh? (Y/N): " -NoNewline -ForegroundColor Yellow
            $response = Read-Host
            
            if ($response -eq 'Y') {
                Clear-StepperState -Confirm:$false
                New-StepperState
            } else {
                Write-Host "Using existing state anyway..." -ForegroundColor Yellow
                $existingState
            }
        } else {
            Write-Host "Resuming from saved state..." -ForegroundColor Cyan
            $existingState
        }
    }
    
    # Show current progress
    Show-StepperProgress -State $state -TotalSteps $totalSteps
    
    # Determine starting point
    $startIndex = $state.CurrentStepIndex
    
    if ($startIndex -ge $totalSteps) {
        $startIndex = 0
    }
    
    Write-Verbose "Starting from step index: $startIndex"
    
    # Execute steps
    for ($i = $startIndex; $i -lt $totalSteps; $i++) {
        $step = $steps[$i]
        
        Show-StepperStepHeader -StepName $step.Name -StepNumber ($i + 1) -TotalSteps $totalSteps
        Write-Host "  $($step.Description)" -ForegroundColor Gray
        Write-Host ""
        
        # Check if already completed
        if ($state.CompletedSteps -contains $step.Name) {
            Write-Host "  This step was already completed." -ForegroundColor Yellow
            Write-Host "  Do you want to skip it? (Y/N): " -NoNewline -ForegroundColor Yellow
            $skip = Read-Host
            
            if ($skip -eq 'Y') {
                Write-Host "  Skipping..." -ForegroundColor Gray
                continue
            } else {
                Write-Host "  Re-running..." -ForegroundColor Gray
            }
        }
        
        # Prepare all results for steps that need them
        $allResults = @{}
        foreach ($completedStep in $state.CompletedSteps) {
            if ($state.StepResults.ContainsKey($completedStep)) {
                $allResults[$completedStep] = $state.StepResults[$completedStep].Result
            }
        }
        
        # Execute the step
        $success = Invoke-StepperStep -Step $step -State $state -AllResults $allResults
        
        # Update current step index
        $state.CurrentStepIndex = $i + 1
        
        # Save state after each step
        Save-StepperState -State $state
        
        if (-not $success) {
            $state.Status = 'Failed'
            Save-StepperState -State $state
            
            Write-Host "`nstepper stopped due to error." -ForegroundColor Red
            Write-Host "State saved. You can resume later with the -Resume switch." -ForegroundColor Yellow
            Write-Host "State file location: $(Get-StateFilePath)" -ForegroundColor Gray
            return
        }
        
        # Prompt to continue after each step (except last)
        if ($i -lt ($totalSteps - 1)) {
            Write-Host "`n  Press Enter to continue to the next step, or Ctrl+C to stop..." -ForegroundColor Cyan
            Read-Host | Out-Null
        }
    }
    
    # Mark as completed
    $state.Status = 'Completed'
    $state.CompletedAt = Get-Date -Format 'o'
    Save-StepperState -State $state
    
    # Show final summary
    Write-Host "`n" + ("=" * 70) -ForegroundColor Green
    Write-Host " stepper Complete!" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green
    
    Show-StepperProgress -State $state -TotalSteps $totalSteps
    
    $totalDuration = ([DateTime]::Parse($state.CompletedAt)) - ([DateTime]::Parse($state.StartedAt))
    Write-Host "Total Duration: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes`n" -ForegroundColor Gray
}
