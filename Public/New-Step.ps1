function New-Step {
    <#
    .SYNOPSIS
        Executes a step in a resumable script.

    .DESCRIPTION
        New-Step allows scripts to be resumed from the last successfully completed step.
        On first execution, it checks for an existing state file and offers to resume.
        Each step is automatically tracked by its location (file:line) in the script.

        The script content is hashed to detect modifications. If the script changes
        between runs, the state is invalidated and execution starts fresh.

    .PARAMETER ScriptBlock
        The code to execute for this step.

    .EXAMPLE
        New-Step {
            Write-Host "Downloading files..."
            Start-Sleep -Seconds 2
        }

        New-Step {
            Write-Host "Processing data..."
            Start-Sleep -Seconds 2
        }

        If the script fails during processing, the next run will skip the download step.

    .NOTES
        State files are stored alongside the script with a .stepper extension.
        Call Stop-Stepper at the end of your script to remove the state file upon successful completion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock
    )

    # Get step identifier and script info
    $stepId = Get-StepIdentifier
    # Extract script path from identifier (format: "path:line")
    $lastColonIndex = $stepId.LastIndexOf(':')
    $scriptPath = $stepId.Substring(0, $lastColonIndex)
    $currentHash = Get-ScriptHash -ScriptPath $scriptPath
    $statePath = Get-StepperStatePath -ScriptPath $scriptPath

    # Initialize $Stepper hashtable in calling script scope if it doesn't exist
    $callingScope = $PSCmdlet.SessionState
    try {
        $existingStepper = $callingScope.PSVariable.Get('Stepper')
        if (-not $existingStepper) {
            $callingScope.PSVariable.Set('Stepper', @{})
        }
    } catch {
        $callingScope.PSVariable.Set('Stepper', @{})
    }

    # Initialize module state on first call in this session
    if (-not $script:StepperSessionState) {
        # Verify the script contains Stop-Stepper
        $scriptContent = Get-Content -Path $scriptPath -Raw
        if ($scriptContent -notmatch 'Stop-Stepper') {
            Write-Host "Script '$scriptPath' does not call Stop-Stepper." -ForegroundColor Yellow
            $response = Read-Host "Add 'Stop-Stepper' to the end of the script? (Y/N)"

            if ($response -eq 'Y' -or $response -eq 'y') {
                Write-Host "Adding 'Stop-Stepper' to the end of the script..." -ForegroundColor Yellow

                # Add Stop-Stepper to the end of the script
                $updatedContent = $scriptContent.TrimEnd()
                if (-not $updatedContent.EndsWith("`n")) {
                    $updatedContent += "`n"
                }
                $updatedContent += "`nStop-Stepper`n"

                Set-Content -Path $scriptPath -Value $updatedContent -NoNewline

                Write-Host "Stop-Stepper added. Please run the script again." -ForegroundColor Green

                # Exit this execution - the script will need to be run again
                throw "Script modified to include Stop-Stepper. Please run the script again."
            }
            else {
                Write-Warning "Continuing without Stop-Stepper. State file will not be cleaned up automatically."
            }
        }

        $script:StepperSessionState = @{
            Initialized       = $false
            RestoreMode       = $false
            TargetStep        = $null
            CurrentScriptPath = $scriptPath
            CurrentScriptHash = $currentHash
            StatePath         = $statePath
        }
    }

    # First step: Check for existing state and prompt user
    if (-not $script:StepperSessionState.Initialized) {
        $script:StepperSessionState.Initialized = $true

        $existingState = Read-StepperState -StatePath $statePath
        
        # Try to load persisted $Stepper data
        $stepperDataPath = Join-Path -Path (Split-Path $statePath -Parent) -ChildPath "stepper-data.json"
        if (Test-Path $stepperDataPath) {
            try {
                $persistedStepper = Get-Content $stepperDataPath -Raw | ConvertFrom-Json
                # Convert JSON object back to hashtable
                $stepperHash = @{}
                $persistedStepper.PSObject.Properties | ForEach-Object {
                    $stepperHash[$_.Name] = $_.Value
                }
                $callingScope.PSVariable.Set('Stepper', $stepperHash)
                Write-Verbose "Loaded persisted \$Stepper data"
            } catch {
                Write-Warning "Failed to load persisted \$Stepper data: $_"
            }
        }

        if ($existingState) {
            # Check if script has been modified
            if ($existingState.ScriptHash -ne $currentHash) {
                Write-Host "Script has been modified since last run. Starting fresh." -ForegroundColor Yellow
                Remove-StepperState -StatePath $statePath
            }
            else {
                # Count total steps in the script by finding all New-Step calls
                $scriptContent = Get-Content -Path $scriptPath -Raw
                $stepMatches = [regex]::Matches($scriptContent, '^\s*New-Step\s+\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                $totalSteps = $stepMatches.Count

                # Find all step line numbers to determine which step number we're on
                $stepLines = @()
                $lineNumber = 1
                foreach ($line in (Get-Content -Path $scriptPath)) {
                    if ($line -match '^\s*New-Step\s+\{') {
                        $stepLines += "${scriptPath}:${lineNumber}"
                    }
                    $lineNumber++
                }

                # Find the index of the last completed step
                $lastStep = $existingState.LastCompletedStep
                $lastStepIndex = $stepLines.IndexOf($lastStep)
                $nextStepNumber = $lastStepIndex + 2  # +1 for next step, +1 because index is 0-based

                $timestamp = $existingState.Timestamp
                Write-Host ""
                Write-Host "Previous run detected (completed $($lastStepIndex + 1) of $totalSteps steps at $timestamp)" -ForegroundColor Cyan

                if ($nextStepNumber -le $totalSteps) {
                    $response = Read-Host "Resume from step $nextStepNumber of ${totalSteps}? (Y/n)"

                    if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
                        Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                        $script:StepperSessionState.RestoreMode = $true
                        $script:StepperSessionState.TargetStep = $lastStep
                    }
                    else {
                        Write-Host "Starting fresh..." -ForegroundColor Yellow
                        Remove-StepperState -StatePath $statePath
                    }
                } else {
                    Write-Host "All steps were completed. Starting fresh..." -ForegroundColor Yellow
                    Remove-StepperState -StatePath $statePath
                }
                Write-Host ""
            }
        }
    }

    # Determine if we should execute this step
    $shouldExecute = $true

    if ($script:StepperSessionState.RestoreMode) {
        # In restore mode: skip steps until we reach the target
        if ($stepId -eq $script:StepperSessionState.TargetStep) {
            # This is the last completed step, skip it and disable restore mode
            Write-Host "[Stepper] Skipping step (already completed): $stepId" -ForegroundColor DarkGray
            $script:StepperSessionState.RestoreMode = $false
            $shouldExecute = $false
        }
        elseif ($script:StepperSessionState.RestoreMode) {
            # Still skipping
            Write-Host "[Stepper] Skipping step: $stepId" -ForegroundColor DarkGray
            $shouldExecute = $false
        }
    }

    # Execute the step if needed
    if ($shouldExecute) {
        Write-Verbose "[Stepper] Executing step: $stepId"

        try {
            & $ScriptBlock

            # Update state file after successful execution
            Write-StepperState -StatePath $statePath -ScriptHash $currentHash -LastCompletedStep $stepId
            
            # Save $Stepper hashtable after successful step execution
            try {
                $stepperData = $callingScope.PSVariable.Get('Stepper').Value
                if ($stepperData -and $stepperData.Count -gt 0) {
                    $stepperDataPath = Join-Path -Path (Split-Path $statePath -Parent) -ChildPath "stepper-data.json"
                    $stepperData | ConvertTo-Json -Depth 10 | Set-Content $stepperDataPath
                    Write-Verbose "Saved \$Stepper data ($($stepperData.Count) items)"
                }
            } catch {
                Write-Warning "Failed to save \$Stepper data: $_"
            }
        }
        catch {
            Write-Error "Step failed at $stepId : $_"
            throw
        }
    }
}
