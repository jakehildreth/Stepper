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

    # Inherit verbose preference by walking the call stack
    $callStack = Get-PSCallStack
    foreach ($frame in $callStack) {
        if ($frame.InvocationInfo.BoundParameters.ContainsKey('Verbose') -and
            $frame.InvocationInfo.BoundParameters['Verbose']) {
            $VerbosePreference = 'Continue'
            break
        }
    }

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
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
        }
    } catch {
        $callingScope.PSVariable.Set('Stepper', @{})
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
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

        # Check for non-resumable code between New-Step blocks and before Stop-Stepper
        $scriptLines = Get-Content -Path $scriptPath

        $blockInfo = Find-NewStepBlocks -ScriptLines $scriptLines
        $newStepBlocks = $blockInfo.NewStepBlocks
        $stopStepperLine = $blockInfo.StopStepperLine

        $nonResumableBlocks = Find-NonResumableCodeBlocks -ScriptLines $scriptLines -NewStepBlocks $newStepBlocks -StopStepperLine $stopStepperLine

        # Process each non-resumable block individually
        if ($nonResumableBlocks.Count -gt 0) {
            $scriptName = Split-Path $scriptPath -Leaf
            $allLinesToRemove = @{}

            foreach ($block in $nonResumableBlocks) {
                $action = Get-NonResumableCodeAction -ScriptName $scriptName -ScriptLines $scriptLines -Block $block

                if ($action -ne 'Ignore') {
                    # Mark these lines with the chosen action
                    foreach ($line in $block.Lines) {
                        $allLinesToRemove[$line] = @{ Action = $action; Code = $scriptLines[$line] }
                    }
                }
            }

            # Apply all the changes
            if ($allLinesToRemove.Count -gt 0) {
                Update-ScriptWithNonResumableActions -ScriptPath $scriptPath -ScriptLines $scriptLines -Actions $allLinesToRemove -NewStepBlocks $newStepBlocks
                exit
            }
        }

        $existingState = Read-StepperState -StatePath $statePath

        # Try to load persisted $Stepper data from state
        if ($existingState -and $existingState.StepperData) {
            try {
                $callingScope.PSVariable.Set('Stepper', $existingState.StepperData)
                $variableNames = ($existingState.StepperData.Keys | Sort-Object) -join ', '
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Loaded `$Stepper data from disk ($variableNames)"
            } catch {
                Write-Warning "Failed to load persisted `$Stepper data: $_"
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

                $timestamp = [DateTime]::Parse($existingState.Timestamp).ToString('yyyy-MM-dd HH:mm:ss')

                # Get available variable names from StepperData
                $availableVars = if ($existingState.StepperData -and $existingState.StepperData.Count -gt 0) {
                    ($existingState.StepperData.Keys | Sort-Object) -join ', '
                } else {
                    'None'
                }

                Write-Host ""
                Write-Host "Incomplete script run detected!" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Total Steps:      $totalSteps" -ForegroundColor Cyan
                Write-Host "Steps Completed:  $($lastStepIndex + 1)" -ForegroundColor Cyan
                Write-Host "Variables:        $availableVars" -ForegroundColor Cyan
                Write-Host "Last Activity:    $timestamp" -ForegroundColor Cyan
                Write-Host ""

                if ($nextStepNumber -le $totalSteps) {
                    # Get the script name and next step line number
                    $scriptName = Split-Path $scriptPath -Leaf
                    $nextStepId = $stepLines[$lastStepIndex + 1]
                    $nextStepLine = ($nextStepId -split ':')[-1]

                    $response = Read-Host "Resume $scriptName from Line ${nextStepLine}? (Y/n)"

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
        # Format step identifier for display messages
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # In restore mode: skip steps until we reach the target
        if ($stepId -eq $script:StepperSessionState.TargetStep) {
            # This is the last completed step, skip it and disable restore mode
            $script:StepperSessionState.RestoreMode = $false
            $shouldExecute = $false
        }
        elseif ($script:StepperSessionState.RestoreMode) {
            # Still skipping
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Skipping step: $displayStepId" -ForegroundColor DarkGray
            $shouldExecute = $false
        }
    }

    # Execute the step if needed
    if ($shouldExecute) {
        # Format step identifier for display (scriptname:line instead of full path)
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # Calculate step number (X/Y)
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $stepMatches = [regex]::Matches($scriptContent, '^\s*New-Step\s+\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $totalSteps = $stepMatches.Count

        # Find all step line numbers
        $stepLines = @()
        $lineNumber = 1
        foreach ($line in (Get-Content -Path $scriptPath)) {
            if ($line -match '^\s*New-Step\s+\{') {
                $stepLines += "${scriptPath}:${lineNumber}"
            }
            $lineNumber++
        }
        $currentStepNumber = $stepLines.IndexOf($stepId) + 1

        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Executing step $currentStepNumber/$totalSteps ($displayStepId)"

        # Show current $Stepper data
        try {
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            if ($stepperData -and $stepperData.Count -gt 0) {
                $variableNames = ($stepperData.Keys | Sort-Object) -join ', '
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Available `$Stepper data ($variableNames)"
            }
        } catch {
            # Ignore if unable to read $Stepper
        }

        try {
            & $ScriptBlock

            # Update state file after successful execution (including $Stepper data)
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            Write-StepperState -StatePath $statePath -ScriptHash $currentHash -LastCompletedStep $stepId -StepperData $stepperData
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Step $currentStepNumber/$totalSteps completed ($displayStepId)"

            if ($stepperData -and $stepperData.Count -gt 0) {
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Saved `$Stepper data ($($stepperData.Count) items)"
            }
        }
        catch {
            Write-Error "Step failed at $stepId : $_"
            throw
        }
    }
}
