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

    # Check if this is the first step of this script execution
    # We use a variable in the calling scope to track initialization per execution
    $initVarName = '__StepperInitialized'
    $isFirstStep = $false
    try {
        $initVar = $callingScope.PSVariable.Get($initVarName)
        if (-not $initVar -or -not $initVar.Value) {
            $isFirstStep = $true
            $callingScope.PSVariable.Set($initVarName, $true)
        }
    } catch {
        $isFirstStep = $true
        $callingScope.PSVariable.Set($initVarName, $true)
    }

    # Initialize execution state on first step
    if ($isFirstStep) {
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

        # Store execution state in calling scope
        $executionState = @{
            RestoreMode       = $false
            TargetStep        = $null
            CurrentScriptPath = $scriptPath
            CurrentScriptHash = $currentHash
            StatePath         = $statePath
        }
        $callingScope.PSVariable.Set('__StepperExecutionState', $executionState)

        # Check script requirements
        $requirementsModified = Test-StepperScriptRequirements -ScriptPath $scriptPath
        if ($requirementsModified) {
            exit
        }

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

                if ($action -eq 'Quit') {
                    Write-Host ""
                    Write-Host "Exiting..." -ForegroundColor Yellow
                    exit
                }

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
                # Script has been modified since last run — prompt user for action
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

                $lastStep = $existingState.LastCompletedStep
                $lastStepIndex = $stepLines.IndexOf($lastStep)
                $nextStepNumber = $lastStepIndex + 2  # +1 for next step, +1 because index is 0-based

                $timestamp = [DateTime]::Parse($existingState.Timestamp).ToString('yyyy-MM-dd HH:mm:ss')
                $availableVars = if ($existingState.StepperData -and $existingState.StepperData.Count -gt 0) {
                    ($existingState.StepperData.Keys | Sort-Object) -join ', '
                } else {
                    'None'
                }

                $scriptName = Split-Path $scriptPath -Leaf
                $nextStepId = $stepLines[$lastStepIndex + 1]
                $nextStepLine = ($nextStepId -split ':')[-1]

                while ($true) {
                    Write-Host ""
                    Write-Host "[!] Incomplete script run detected, but $scriptName has been modified." -ForegroundColor Magenta
                    Write-Host ""
                    Write-Host "Total Steps:      $totalSteps"
                    Write-Host "Steps Completed:  $($lastStepIndex + 1)"
                    Write-Host "Variables:        $availableVars"
                    Write-Host "Last Activity:    $timestamp"
                    Write-Host ""

                    Write-Host "How would you like to proceed?"
                    Write-Host ""
                    Write-Host "  [R] Resume $scriptName from Line ${nextStepLine} (May produce inconsistent results)" -ForegroundColor White
                    Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                    Write-Host "  [M] More details" -ForegroundColor White
                    Write-Host "  [Q] Quit" -ForegroundColor White
                    Write-Host ""
                    Write-Host "Choice? [" -NoNewline
                    Write-Host "r" -NoNewline -ForegroundColor White
                    Write-Host "/S" -NoNewline -ForegroundColor Cyan
                    Write-Host "/m/q]: " -NoNewline
                    $response = Read-Host

                    if ($response -eq '' -or $response -eq 'S' -or $response -eq 's') {
                        Write-Host "Starting fresh..." -ForegroundColor Yellow
                        Remove-StepperState -StatePath $statePath
                        break
                    }
                    elseif ($response -eq 'R' -or $response -eq 'r') {
                        Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                        $executionState.RestoreMode = $true
                        $executionState.TargetStep = $lastStep
                        break
                    }
                    elseif ($response -eq 'M' -or $response -eq 'm') {
                        Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine -ShowHashComparison

                        # Re-display the bottom inline menu and accept an immediate choice
                        Write-Host "  [R] Resume $scriptName from Line ${nextStepLine} (May produce inconsistent results)" -ForegroundColor White
                        Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                        Write-Host "  [M] More details" -ForegroundColor White
                        Write-Host "  [Q] Quit" -ForegroundColor White
                        Write-Host ""
Write-Host "Choice? [r/S/m/q]: " -NoNewline
                        $moreResponse = Read-Host

                        if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                            Write-Host "Starting fresh..." -ForegroundColor Yellow
                            Remove-StepperState -StatePath $statePath
                            break
                        }
                        elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                            Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                            $executionState.RestoreMode = $true
                            $executionState.TargetStep = $lastStep
                            break
                        }
                        elseif ($moreResponse -eq 'M' -or $moreResponse -eq 'm') {
                            # Re-display details (loop)
                            continue
                        }
                        elseif ($moreResponse -eq 'Q' -or $moreResponse -eq 'q') {
                            Write-Host ""
                            Write-Host "Exiting..." -ForegroundColor Yellow
                            exit
                        }
                        else {
                            # Default to Start over for invalid input
                            Write-Host "Starting fresh..." -ForegroundColor Yellow
                            Remove-StepperState -StatePath $statePath
                            break
                        }
                    }
                    elseif ($response -eq 'Q' -or $response -eq 'q') {
                        Write-Host ""
                        Write-Host "Exiting..." -ForegroundColor Yellow
                        exit
                    }
                    else {
                        # Default to Start over for invalid input
                        Write-Host "Starting fresh..." -ForegroundColor Yellow
                        Remove-StepperState -StatePath $statePath
                        break
                    }
                }
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
                Write-Host "[!] Incomplete script run detected!" -ForegroundColor Magenta
                Write-Host ""
                Write-Host "Total Steps:      $totalSteps"
                Write-Host "Steps Completed:  $($lastStepIndex + 1)"
                Write-Host "Variables:        $availableVars"
                Write-Host "Last Activity:    $timestamp"
                Write-Host ""

                if ($nextStepNumber -le $totalSteps) {
                    # Get the script name and next step line number
                    $scriptName = Split-Path $scriptPath -Leaf
                    $nextStepId = $stepLines[$lastStepIndex + 1]
                    $nextStepLine = ($nextStepId -split ':')[-1]

                    while ($true) {
                        Write-Host "How would you like to proceed?"
                        Write-Host ""
                        Write-Host "  [R] Resume $scriptName from Line ${nextStepLine} (Default)" -ForegroundColor Cyan
                        Write-Host "  [S] Start over" -ForegroundColor White
                        Write-Host "  [M] More details" -ForegroundColor White
                        Write-Host "  [Q] Quit" -ForegroundColor White
                        Write-Host ""
                        Write-Host "Choice? [" -NoNewline
                        Write-Host "R" -NoNewline -ForegroundColor Cyan
                        Write-Host "/s/m/q]: " -NoNewline
                        $response = Read-Host

                        if ($response -eq '' -or $response -eq 'R' -or $response -eq 'r') {
                            Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                            $executionState.RestoreMode = $true
                            $executionState.TargetStep = $lastStep
                            break
                        }
                        elseif ($response -eq 'S' -or $response -eq 's') {
                            Write-Host "Starting fresh..." -ForegroundColor Yellow
                            Remove-StepperState -StatePath $statePath
                            break
                        }
                        elseif ($response -eq 'M' -or $response -eq 'm') {
                            Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine

                            # Print the action menu again at the bottom of the details and accept an immediate choice
                            Write-Host "  [R] Resume $scriptName from Line ${nextStepLine} (Default)" -ForegroundColor Cyan
                            Write-Host "  [S] Start over" -ForegroundColor White
                            Write-Host "  [M] More details" -ForegroundColor White
                            Write-Host "  [Q] Quit" -ForegroundColor White
                            Write-Host ""
                            Write-Host "Choice? [R/s/m/q]: " -NoNewline
                            $moreResponse = Read-Host

                            if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                                Write-Host "Starting fresh..." -ForegroundColor Yellow
                                Remove-StepperState -StatePath $statePath
                                break
                            }
                            elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                                Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                                $executionState.RestoreMode = $true
                                $executionState.TargetStep = $lastStep
                                break
                            }
                            elseif ($moreResponse -eq 'M' -or $moreResponse -eq 'm') {
                                # Re-display details (loop)
                                continue
                            }
                            elseif ($moreResponse -eq 'Q' -or $moreResponse -eq 'q') {
                                Write-Host ""
                                Write-Host "Exiting..." -ForegroundColor Yellow
                                exit
                            }
                            else {
                                # Default to Start over for invalid input
                                Write-Host "Starting fresh..." -ForegroundColor Yellow
                                Remove-StepperState -StatePath $statePath
                                break
                            }
                        }
                        elseif ($response -eq 'Q' -or $response -eq 'q') {
                            Write-Host ""
                            Write-Host "Exiting..." -ForegroundColor Yellow
                            exit
                        }
                        else {
                            # Default to Resume for invalid input
                            Write-Host "Resuming from step $nextStepNumber..." -ForegroundColor Green
                            $executionState.RestoreMode = $true
                            $executionState.TargetStep = $lastStep
                            break
                        }
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

    # Get execution state from calling scope
    try {
        $executionState = $callingScope.PSVariable.Get('__StepperExecutionState').Value
    } catch {
        $executionState = $null
    }

    if ($executionState -and $executionState.RestoreMode) {
        # Format step identifier for display messages
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # In restore mode: skip steps until we reach the target
        if ($stepId -eq $executionState.TargetStep) {
            # This is the last completed step, skip it and disable restore mode
            $executionState.RestoreMode = $false
            $shouldExecute = $false
        }
        elseif ($executionState.RestoreMode) {
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
            # Persist state including the script contents for better change inspection
            $scriptContents = Get-Content -Path $scriptPath -Raw
            Write-StepperState -StatePath $statePath -ScriptHash $currentHash -LastCompletedStep $stepId -StepperData $stepperData -ScriptContents $scriptContents
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
