function Start-Stepper {
    <#
    .SYNOPSIS
        Main function to run the multi-step Stepper.
    
    .DESCRIPTION
        Orchestrates the execution of all Stepper steps, manages state
        persistence, handles errors, and provides progress feedback.
        
        By default, resumes from the last saved state. Use -Fresh to start over.
    
    .PARAMETER Fresh
        Start a completely new Stepper, ignoring any saved state.
    
    .PARAMETER ConfigPath
        Path to the Stepper configuration JSON file. If not specified, attempts to find
        a JSON file with the same base name as the calling script (e.g., MyScript.ps1 -> MyScript.json).
        Falls back to stepper-config.json in the module root if no match is found.
    
    .EXAMPLE
        Start-Stepper
        
        Automatically finds a JSON config with the same name as the calling script.
        Resumes from the last checkpoint (default behavior).
    
    .EXAMPLE
        Start-Stepper -Fresh
        
        Starts a completely new Stepper from the beginning.
    
    .EXAMPLE
        Start-Stepper -ConfigPath ".\my-steps.json"
        
        Uses a custom configuration file.
    
    .NOTES
        State is automatically saved after each step.
        The Stepper can be safely interrupted and resumed later.
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
    
    # Get all Stepper steps
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
        Write-Host "Starting fresh Stepper (ignoring saved state)..." -ForegroundColor Cyan
        New-StepperState
    } else {
        # Default behavior: try to resume
        $existingState = Get-StepperState
        
        # Default behavior: try to resume
        $existingState = Get-StepperState
        
        if ($existingState.Status -eq 'Completed') {
            Write-Host "Previous Stepper was completed." -ForegroundColor Yellow
            
            $title = "Start New Stepper"
            $message = "Do you want to start a new Stepper?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Start a new Stepper from the beginning"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Exit without running"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.UI.PromptForChoice($title, $message, $options, 1)
            
            if ($choice -eq 0) {
                New-StepperState
            } else {
                Write-Host "Exiting..." -ForegroundColor Gray
                return
            }
        } elseif (-not (Test-StepperStateValidity -State $existingState)) {
            Write-Host "Saved state is invalid or too old." -ForegroundColor Yellow
            
            $title = "Invalid State"
            $message = "Do you want to start fresh?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Clear state and start over"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Use existing state anyway"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.UI.PromptForChoice($title, $message, $options, 0)
            
            if ($choice -eq 0) {
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
            
            $title = "Step Already Completed"
            $message = "Do you want to skip this step?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Skip this step and continue"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Re-run this step"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.UI.PromptForChoice($title, $message, $options, 0)
            
            if ($choice -eq 0) {
                Write-Host "  Skipping..." -ForegroundColor Gray
                continue
            } else {
                Write-Host "  Re-running..." -ForegroundColor Gray
            }
        }
        
        # Prepare all results for steps that need them
        # Array index matches step number: AllResults[1] = Step 1 result, etc.
        # AllResults[0] is $null to make indexing intuitive
        $allResults = @($null)
        for ($j = 0; $j -lt $i; $j++) {
            $previousStep = $steps[$j]
            if ($state.CompletedSteps -contains $previousStep.Name -and $state.StepResults.ContainsKey($previousStep.Name)) {
                $allResults += $state.StepResults[$previousStep.Name].Result
            } else {
                $allResults += $null
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
            
            Write-Host "`nStepper stopped due to error." -ForegroundColor Red
            Write-Host "State saved. You can resume later with the -Resume switch." -ForegroundColor Yellow
            Write-Host "State file location: $(Get-StateFilePath)" -ForegroundColor Gray
            return
        }
        
        # Prompt to continue after each step (except last)
        if ($i -lt ($totalSteps - 1)) {
            Write-Host ""
            $title = "Continue to Next Step"
            $message = "Ready to continue?"
            $continue = New-Object System.Management.Automation.Host.ChoiceDescription "&Continue", "Continue to the next step"
            $stop = New-Object System.Management.Automation.Host.ChoiceDescription "&Stop", "Stop and save progress (Ctrl+C also works)"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($continue, $stop)
            $choice = $host.UI.PromptForChoice($title, $message, $options, 0)
            
            if ($choice -eq 1) {
                Write-Host "`nStopping... Progress has been saved." -ForegroundColor Yellow
                return
            }
        }
    }
    
    # Mark as completed
    $state.Status = 'Completed'
    $state.CompletedAt = Get-Date -Format 'o'
    Save-StepperState -State $state
    
    # Show final summary
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Green
    Write-Host " Stepper Complete!" -ForegroundColor Green
    Write-Host ("=" * 70) -ForegroundColor Green
    
    Show-StepperProgress -State $state -TotalSteps $totalSteps
    
    $totalDuration = ([DateTime]::Parse($state.CompletedAt)) - ([DateTime]::Parse($state.StartedAt))
    Write-Host "Total Duration: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes`n" -ForegroundColor Gray
}
