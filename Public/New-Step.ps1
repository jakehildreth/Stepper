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
    # This technique allows -Verbose to propagate from the parent script
    # without requiring it as an explicit parameter on New-Step calls
    $callStack = Get-PSCallStack
    foreach ($frame in $callStack) {
        # Check if any caller in the stack has -Verbose enabled
        if ($frame.InvocationInfo.BoundParameters.ContainsKey('Verbose') -and
            $frame.InvocationInfo.BoundParameters['Verbose']) {
            # Enable verbose output for this function and all subsequent calls
            $VerbosePreference = 'Continue'
            break
        }
    }

    # Get step identifier and script info
    # Each step is uniquely identified by its file location (path:line)
    # This allows Stepper to track which steps have been completed
    try {
        $stepId = Get-StepIdentifier
    }
    catch {
        throw "Stepper cannot determine the step identifier. Ensure New-Step is called from a script file and not from the console or an unsaved file."
    }
    # Extract script path from identifier (format: "path:line")
    # Example: "C:\Scripts\deploy.ps1:42" becomes "C:\Scripts\deploy.ps1"
    $lastColonIndex = $stepId.LastIndexOf(':')
    $scriptPath = $stepId.Substring(0, $lastColonIndex)
    
    #Region Check if this is an unsaved file
    try {
        $fullPath = [System.IO.Path]::GetFullPath($scriptPath)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Stepper cannot be used with unsaved files. Please save the script first."
        }
    }
    catch {
        throw "Stepper cannot be used with unsaved files. Please save the script first."
    }
    #EndRegion Check if this is an unsaved file
    
    # Calculate SHA256 hash of the script file content
    # This detects if the script has been modified since the last run
    $currentHash = Get-ScriptHash -ScriptPath $scriptPath
    
    # Get the path where state will be saved (script.ps1 -> script.ps1.stepper)
    $statePath = Get-StepperStatePath -ScriptPath $scriptPath

    # Initialize $Stepper hashtable in calling script scope if it doesn't exist
    # This allows users to share data between steps using $Stepper.VariableName
    # We use $PSCmdlet.SessionState to access the caller's scope, not our own
    $callingScope = $PSCmdlet.SessionState
    try {
        $existingStepper = $callingScope.PSVariable.Get('Stepper')
        if (-not $existingStepper) {
            # Create an empty hashtable in the caller's scope
            $callingScope.PSVariable.Set('Stepper', @{})
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
        }
    } catch {
        # If Get fails (variable doesn't exist), initialize it
        $callingScope.PSVariable.Set('Stepper', @{})
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
    }

    # Check if this is the first step of this script execution
    # We use a variable in the calling scope to track initialization per execution
    # This ensures one-time setup only happens once, even if multiple steps execute
    $initVarName = '__StepperInitialized'
    $isFirstStep = $false
    try {
        $initVar = $callingScope.PSVariable.Get($initVarName)
        if (-not $initVar -or -not $initVar.Value) {
            # This is the first step, mark initialization as complete
            $isFirstStep = $true
            $callingScope.PSVariable.Set($initVarName, $true)
        }
    } catch {
        # Variable doesn't exist yet, so this must be the first step
        $isFirstStep = $true
        $callingScope.PSVariable.Set($initVarName, $true)
    }

    # Initialize execution state on first step
    # This setup code only runs once per script execution, not for every step
    if ($isFirstStep) {
        # Store execution state in calling scope
        # This state is shared across all New-Step calls in this execution
        # RestoreMode: Whether we're skipping steps to resume from a previous run
        # TargetStep: The last completed step we're trying to reach (then resume after)
        $executionState = @{
            RestoreMode       = $false
            TargetStep        = $null
            CurrentScriptPath = $scriptPath
            CurrentScriptHash = $currentHash
            StatePath         = $statePath
        }
        $callingScope.PSVariable.Set('__StepperExecutionState', $executionState)

        # Check script requirements (declarations) first
        # Ensures the script has proper #Requires statements for modules
        $requirementsModified = Test-StepperScriptRequirements -ScriptPath $scriptPath
        if ($requirementsModified) {
            # Script was modified to add requirements, must restart
            exit
        }

        # Check for non-resumable code between New-Step blocks and before Stop-Stepper
        # Non-resumable code is code that would execute every time, even when resuming
        # Examples: variable assignments, function calls outside of New-Step blocks
        $scriptLines = Get-Content -Path $scriptPath

        # Find all New-Step blocks and Stop-Stepper location in the script
        $blockInfo = Find-NewStepBlocks -ScriptLines $scriptLines
        $newStepBlocks = $blockInfo.NewStepBlocks
        $stopStepperLine = $blockInfo.StopStepperLine

        # Identify code that would execute on every run (not inside New-Step)
        $nonResumableBlocks = Find-NonResumableCodeBlocks -ScriptLines $scriptLines -NewStepBlocks $newStepBlocks -StopStepperLine $stopStepperLine

        # Process each non-resumable block individually
        # Give user options to wrap it in New-Step, add ignore region, or remove it
        if ($nonResumableBlocks.Count -gt 0) {
            $scriptName = Split-Path $scriptPath -Leaf
            $allLinesToRemove = @{}

            foreach ($block in $nonResumableBlocks) {
                # Prompt user for action on this specific block
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

        # Verify the script contains Stop-Stepper (last check)
        $scriptContent = Get-Content -Path $scriptPath -Raw
        if ($scriptContent -notmatch 'Stop-Stepper') {
            $scriptName = Split-Path $scriptPath -Leaf
            Write-Host ""
            Write-Host "[!] Script '$scriptName' does not call Stop-Stepper." -ForegroundColor Magenta
            Write-Host ""
            Write-Host "Stop-Stepper ensures the state file is removed when the script completes successfully."
            Write-Host ""
            Write-Host "How would you like to proceed?"
            Write-Host ""
            Write-Host "  [A] Add 'Stop-Stepper' to the end of the script (Default)" -ForegroundColor Cyan
            Write-Host "  [C] Continue without Stop-Stepper" -ForegroundColor White
            Write-Host "  [Q] Quit" -ForegroundColor White
            Write-Host ""
            Write-Host "Choice? [" -NoNewline
            Write-Host "A" -NoNewline -ForegroundColor Cyan
            Write-Host "/c/q]: " -NoNewline
            $response = Read-Host

            if ($response -eq '' -or $response -eq 'A' -or $response -eq 'a') {
                # Add Stop-Stepper to the end of the script
                $updatedContent = $scriptContent.TrimEnd()
                if (-not $updatedContent.EndsWith("`n")) {
                    $updatedContent += "`n"
                }
                $updatedContent += "`nStop-Stepper`n"

                Set-Content -Path $scriptPath -Value $updatedContent -NoNewline

                # Delete state file since script was modified
                Remove-StepperState -StatePath $statePath

                Write-Host ""
                Write-Host "Stop-Stepper added. Please re-run $scriptName." -ForegroundColor Green

                # Exit this execution - the script will need to be run again
                exit
            }
            elseif ($response -eq 'C' -or $response -eq 'c') {
                Write-Warning "Continuing without Stop-Stepper. State file will not be cleaned up automatically."
            }
            elseif ($response -eq 'Q' -or $response -eq 'q') {
                Write-Host ""
                Write-Host "Exiting..." -ForegroundColor Yellow
                exit
            }
            else {
                # Default to Add for invalid input
                # Add Stop-Stepper to the end of the script
                $updatedContent = $scriptContent.TrimEnd()
                if (-not $updatedContent.EndsWith("`n")) {
                    $updatedContent += "`n"
                }
                $updatedContent += "`nStop-Stepper`n"

                Set-Content -Path $scriptPath -Value $updatedContent -NoNewline

                # Delete state file since script was modified
                Remove-StepperState -StatePath $statePath

                Write-Host ""
                Write-Host "Stop-Stepper added. Please re-run $scriptName." -ForegroundColor Green

                # Exit this execution - the script will need to be run again
                exit
            }
        }

        # Read existing state file if it exists
        # State contains: script hash, last completed step, timestamp, and $Stepper data
        $existingState = Read-StepperState -StatePath $statePath

        # Try to load persisted $Stepper data from state
        # This restores variables saved from the previous incomplete run
        if ($existingState -and $existingState.StepperData) {
            try {
                # Restore the $Stepper hashtable in the caller's scope
                $callingScope.PSVariable.Set('Stepper', $existingState.StepperData)
                $variableNames = ($existingState.StepperData.Keys | Sort-Object) -join ', '
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Loaded `$Stepper data from disk ($variableNames)"
            } catch {
                Write-Warning "Failed to load persisted `$Stepper data: $_"
            }
        }

        if ($existingState) {
            # Check if script has been modified since the state was saved
            # If hashes don't match, the script has changed and may not be safe to resume
            if ($existingState.ScriptHash -ne $currentHash) {
                # Script has been modified since last run — prompt user for action
                # User can choose to resume anyway (risky) or start over (safe)
                $scriptContent = Get-Content -Path $scriptPath -Raw
                # Count total New-Step blocks using regex
                $stepMatches = [regex]::Matches($scriptContent, '^\s*New-Step\s+\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                $totalSteps = $stepMatches.Count

                # Find all step line numbers
                $stepLines = @()
                $lineNumber = 1
                $lines = $scriptContent -split "`r?`n"
                foreach ($line in $lines) {
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
                        Write-Host ""
                        Write-Host "Resuming from Step $nextStepNumber..." -ForegroundColor Green
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
                            Write-Host ""
                            Write-Host "Resuming from Step $nextStepNumber..." -ForegroundColor Green
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
                            Write-Host ""
                            Write-Host "Resuming from Step $nextStepNumber..." -ForegroundColor Green
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
                                Write-Host ""
                                Write-Host "Resuming from Step $nextStepNumber..." -ForegroundColor Green
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
                            Write-Host ""
                            Write-Host "Resuming from Step $nextStepNumber..." -ForegroundColor Green
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
    # By default, execute every step unless we're in restore mode
    $shouldExecute = $true

    # Get execution state from calling scope
    # This state tracks whether we're skipping steps during a resume
    try {
        $executionState = $callingScope.PSVariable.Get('__StepperExecutionState').Value
    } catch {
        $executionState = $null
    }

    if ($executionState -and $executionState.RestoreMode) {
        # Format step identifier for display messages
        # Convert full path to just filename for cleaner output
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # In restore mode: skip steps until we reach the target
        # TargetStep is the last step that completed successfully
        if ($stepId -eq $executionState.TargetStep) {
            # This is the last completed step, skip it and disable restore mode
            # The next step will execute normally
            $executionState.RestoreMode = $false
            $shouldExecute = $false
        }
        elseif ($executionState.RestoreMode) {
            # Still skipping earlier steps that already completed
            $shouldExecute = $false
        }
    }

    # Execute the step if needed
    # Either this is a fresh run or we've finished skipping completed steps
    if ($shouldExecute) {
        # Format step identifier for display (scriptname:line instead of full path)
        # Makes verbose output more readable
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # Calculate step number (X/Y) for progress indication
        # Count total New-Step blocks in the script
        $scriptContent = Get-Content -Path $scriptPath -Raw
        $stepMatches = [regex]::Matches($scriptContent, '^\s*New-Step\s+\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $totalSteps = $stepMatches.Count

        # Find all step line numbers to determine current step position
        $stepLines = @()
        $lineNumber = 1
        foreach ($line in (Get-Content -Path $scriptPath)) {
            if ($line -match '^\s*New-Step\s+\{') {
                $stepLines += "${scriptPath}:${lineNumber}"
            }
            $lineNumber++
        }
        # Find the current step's position in the list (1-based index)
        $currentStepNumber = $stepLines.IndexOf($stepId) + 1

        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Executing step $currentStepNumber/$totalSteps ($displayStepId)"

        # Show current $Stepper data available to this step
        # Helps with debugging to see what variables are accessible
        try {
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            if ($stepperData -and $stepperData.Count -gt 0) {
                $variableNames = ($stepperData.Keys | Sort-Object) -join ', '
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Available `$Stepper data ($variableNames)"
            }
        } catch {
            # Ignore if unable to read $Stepper (shouldn't happen)
        }

        try {
            # Execute the user's script block using the call operator (&)
            # This runs the code inside New-Step { ... }
            & $ScriptBlock

            # Update state file after successful execution (including $Stepper data)
            # Save current state so we can resume from here if script fails later
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            # Persist state including the script contents for better change inspection
            # Script contents help detect modifications when resuming
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
