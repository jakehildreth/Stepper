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

    .PARAMETER Name
        Optional name for this step. Displayed in verbose output and resume prompts.

    .PARAMETER ScriptBlock
        The code to execute for this step.

    .EXAMPLE
        New-Step 'Download Files' {
            Write-Host "Downloading files..."
            Start-Sleep -Seconds 2
        }

        New-Step 'Process Data' {
            Write-Host "Processing data..."
            Start-Sleep -Seconds 2
        }

        If the script fails during processing, the next run will skip the download step.
        $Stepper.StepName and $Stepper.StepNumber are available inside each block.

    .EXAMPLE
        New-Step {
            Write-Host "Unnamed step — backward-compatible syntax."
        }

    .NOTES
        State files are stored alongside the script with a .stepper extension.
        Call Stop-Stepper at the end of your script to remove the state file upon successful completion.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Unnamed')]
    param(
        [Parameter(ParameterSetName = 'Named', Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Named', Mandatory, Position = 1)]
        [Parameter(ParameterSetName = 'Unnamed', Mandatory, Position = 0)]
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
    try {
        $stepId = Get-StepIdentifier
    }
    catch {
        $exception = [System.InvalidOperationException]::new('Stepper cannot determine the step identifier. Ensure New-Step is called from a script file and not from the console or an unsaved file.', $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StepIdentifierNotFound',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    # Extract script path from identifier (format: "path:line")
    $lastColonIndex = $stepId.LastIndexOf(':')
    $scriptPath = $stepId.Substring(0, $lastColonIndex)
    
    #Region Check if this is an unsaved file
    try {
        $fullPath = [System.IO.Path]::GetFullPath($scriptPath)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $exception = [System.IO.FileNotFoundException]::new('Stepper cannot be used with unsaved files. Please save the script first.')
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'UnsavedScriptFile',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $scriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    catch {
        $exception = [System.IO.FileNotFoundException]::new('Stepper cannot be used with unsaved files. Please save the script first.', $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'UnsavedScriptFile',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            $scriptPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    #EndRegion Check if this is an unsaved file
    
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
        # Store execution state in calling scope
        $executionState = @{
            RestoreMode       = $false
            TargetStep        = $null
            CurrentScriptPath = $scriptPath
            CurrentScriptHash = $currentHash
            StatePath         = $statePath
        }
        $callingScope.PSVariable.Set('__StepperExecutionState', $executionState)

        # Check script requirements (declarations) first
        $requirementsModified = Test-StepperScriptRequirements -ScriptPath $scriptPath
        if ($requirementsModified) {
            exit
        }

        # Check for non-resumable code between New-Step blocks and before Stop-Stepper
        try {
            $scriptLines = Get-Content -Path $scriptPath -ErrorAction Stop
        }
        catch {
            $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ScriptReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $scriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

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

        # Verify the script contains Stop-Stepper (last check)
        try {
            $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
        }
        catch {
            $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ScriptReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $scriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        
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
            try {
                $response = Read-Host
            }
            catch {
                # Non-interactive context - default to Continue
                $response = 'c'
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Continue"
            }

            if ($response -eq '' -or $response -eq 'A' -or $response -eq 'a') {
                # Add Stop-Stepper to the end of the script
                $updatedContent = $scriptContent.TrimEnd()
                if (-not $updatedContent.EndsWith("`n")) {
                    $updatedContent += "`n"
                }
                $updatedContent += "`nStop-Stepper`n"

                try {
                    Set-Content -Path $scriptPath -Value $updatedContent -NoNewline -ErrorAction Stop
                }
                catch {
                    $exception = [System.IO.IOException]::new("Failed to write to script file '$scriptPath'", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'ScriptWriteFailed',
                        [System.Management.Automation.ErrorCategory]::WriteError,
                        $scriptPath
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }

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

                try {
                    Set-Content -Path $scriptPath -Value $updatedContent -NoNewline -ErrorAction Stop
                }
                catch {
                    $exception = [System.IO.IOException]::new("Failed to write to script file '$scriptPath'", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'ScriptWriteFailed',
                        [System.Management.Automation.ErrorCategory]::WriteError,
                        $scriptPath
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }

                # Delete state file since script was modified
                Remove-StepperState -StatePath $statePath

                Write-Host ""
                Write-Host "Stop-Stepper added. Please re-run $scriptName." -ForegroundColor Green

                # Exit this execution - the script will need to be run again
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
                try {
                    $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
                }
                catch {
                    $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'ScriptReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $scriptPath
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
                $stepMatches = [regex]::Matches($scriptContent, '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                $totalSteps = $stepMatches.Count

                # Find all step line numbers and names
                $stepLines = @()
                $stepNames = @()
                $lineNumber = 1
                $lines = $scriptContent -split "`r?`n"
                foreach ($line in $lines) {
                    if ($line -match '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{') {
                        $stepLines += "${scriptPath}:${lineNumber}"
                        if ($line -match '(?i)^\s*New-Step\s+(?:-Name\s+)?(?:"([^"]*)"|''([^'']*)'')') {
                            $stepNames += if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                        } else {
                            $stepNames += $null
                        }
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
                $nextStepName = $stepNames[$lastStepIndex + 1]
                $nextStepDisplay = if ($nextStepName) { "$nextStepName (Step $nextStepNumber, Line $nextStepLine)" } else { "Step $nextStepNumber (Line $nextStepLine)" }
                $lastStepLine = ($lastStep -split ':')[-1]
                $lastStepDisplay = if ($existingState.LastCompletedStepName) { "$($existingState.LastCompletedStepName) (Step $($lastStepIndex + 1), Line $lastStepLine)" } else { "Step $($lastStepIndex + 1) (Line $lastStepLine)" }

                while ($true) {
                    Write-Host ""
                    Write-Host "[!] Incomplete script run detected, but $scriptName has been modified." -ForegroundColor Magenta
                    Write-Host ""
                    Write-Host "Total Steps:           $totalSteps"
                    Write-Host "Steps Completed:       $($lastStepIndex + 1)"
                    Write-Host "Last Completed Step:   $lastStepDisplay"
                    Write-Host "Variables:             $availableVars"
                    Write-Host "Last Activity:         $timestamp"
                    Write-Host ""

                    Write-Host "How would you like to proceed?"
                    Write-Host ""
                    Write-Host "  [R] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                    Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                    Write-Host "  [M] More details" -ForegroundColor White
                    Write-Host "  [Q] Quit" -ForegroundColor White
                    Write-Host ""
                    Write-Host "Choice? [" -NoNewline
                    Write-Host "r" -NoNewline -ForegroundColor White
                    Write-Host "/S" -NoNewline -ForegroundColor Cyan
                    Write-Host "/m/q]: " -NoNewline
                    try {
                        $response = Read-Host
                    }
                    catch {
                        # Non-interactive context - default to Start over (safer)
                        $response = 's'
                        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Start over"
                    }

                    if ($response -eq '' -or $response -eq 'S' -or $response -eq 's') {
                        Write-Host "Starting fresh..." -ForegroundColor Yellow
                        Remove-StepperState -StatePath $statePath
                        break
                    }
                    elseif ($response -eq 'R' -or $response -eq 'r') {
                        Write-Host ""
                        Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                        $executionState.RestoreMode = $true
                        $executionState.TargetStep = $lastStep
                        break
                    }
                    elseif ($response -eq 'M' -or $response -eq 'm') {
                        Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine -NextStepName $nextStepName -NextStepNumber $nextStepNumber -ShowHashComparison

                        # Re-display the bottom inline menu and accept an immediate choice
                        Write-Host "  [R] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                        Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                        Write-Host "  [Q] Quit" -ForegroundColor White
                        Write-Host ""
                        Write-Host "Choice? [r/S/q]: " -NoNewline
                        try {
                            $moreResponse = Read-Host
                        }
                        catch {
                            # Non-interactive context - default to Start over (safer)
                            $moreResponse = 's'
                            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Start over"
                        }

                        if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                            Write-Host "Starting fresh..." -ForegroundColor Yellow
                            Remove-StepperState -StatePath $statePath
                            break
                        }
                        elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                            Write-Host ""
                            Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                            $executionState.RestoreMode = $true
                            $executionState.TargetStep = $lastStep
                            break
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
                try {
                    $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
                }
                catch {
                    $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'ScriptReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $scriptPath
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
                $stepMatches = [regex]::Matches($scriptContent, '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
                $totalSteps = $stepMatches.Count

                # Find all step line numbers and names to determine which step number we're on
                $stepLines = @()
                $stepNames = @()
                $lineNumber = 1
                try {
                    foreach ($line in (Get-Content -Path $scriptPath -ErrorAction Stop)) {
                        if ($line -match '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{') {
                            $stepLines += "${scriptPath}:${lineNumber}"
                            if ($line -match '(?i)^\s*New-Step\s+(?:-Name\s+)?(?:"([^"]*)"|''([^'']*)'')') {
                                $stepNames += if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                            } else {
                                $stepNames += $null
                            }
                        }
                        $lineNumber++
                    }
                }
                catch {
                    $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'ScriptReadFailed',
                        [System.Management.Automation.ErrorCategory]::ReadError,
                        $scriptPath
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
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

                $lastStepLine = ($lastStep -split ':')[-1]
                $lastStepDisplay = if ($existingState.LastCompletedStepName) { "$($existingState.LastCompletedStepName) (Step $($lastStepIndex + 1), Line $lastStepLine)" } else { "Step $($lastStepIndex + 1) (Line $lastStepLine)" }

                Write-Host ""
                Write-Host "[!] Incomplete script run detected!" -ForegroundColor Magenta
                Write-Host ""
                Write-Host "Total Steps:           $totalSteps"
                Write-Host "Steps Completed:       $($lastStepIndex + 1)"
                Write-Host "Last Completed Step:   $lastStepDisplay"
                Write-Host "Variables:             $availableVars"
                Write-Host "Last Activity:         $timestamp"
                Write-Host ""

                if ($nextStepNumber -le $totalSteps) {
                    # Get the script name and next step line number
                    $scriptName = Split-Path $scriptPath -Leaf
                    $nextStepId = $stepLines[$lastStepIndex + 1]
                    $nextStepLine = ($nextStepId -split ':')[-1]
                    $nextStepName = $stepNames[$lastStepIndex + 1]
                    $nextStepDisplay = if ($nextStepName) { "$nextStepName (Step $nextStepNumber, Line $nextStepLine)" } else { "Step $nextStepNumber (Line $nextStepLine)" }

                    while ($true) {
                        Write-Host "How would you like to proceed?"
                        Write-Host ""
                        Write-Host "  [R] Resume $scriptName from $nextStepDisplay (Default)" -ForegroundColor Cyan
                        Write-Host "  [S] Start over" -ForegroundColor White
                        Write-Host "  [M] More details" -ForegroundColor White
                        Write-Host "  [Q] Quit" -ForegroundColor White
                        Write-Host ""
                        Write-Host "Choice? [" -NoNewline
                        Write-Host "R" -NoNewline -ForegroundColor Cyan
                        Write-Host "/s/m/q]: " -NoNewline
                        try {
                            $response = Read-Host
                        }
                        catch {
                            # Non-interactive context - default to Resume (safer for unchanged scripts)
                            $response = 'r'
                            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Resume"
                        }

                        if ($response -eq '' -or $response -eq 'R' -or $response -eq 'r') {
                            Write-Host ""
                            Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
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
                            Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine -NextStepName $nextStepName -NextStepNumber $nextStepNumber

                            # Print the action menu again at the bottom of the details and accept an immediate choice
                            Write-Host "  [R] Resume $scriptName from $nextStepDisplay (Default)" -ForegroundColor Cyan
                            Write-Host "  [S] Start over" -ForegroundColor White
                            Write-Host "  [Q] Quit" -ForegroundColor White
                            Write-Host ""
                            Write-Host "Choice? [R/s/q]: " -NoNewline
                            try {
                                $moreResponse = Read-Host
                            }
                            catch {
                                # Non-interactive context - default to Resume (safer for unchanged scripts)
                                $moreResponse = 'r'
                                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Resume"
                            }

                            if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                                Write-Host "Starting fresh..." -ForegroundColor Yellow
                                Remove-StepperState -StatePath $statePath
                                break
                            }
                            elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                                Write-Host ""
                                Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                                $executionState.RestoreMode = $true
                                $executionState.TargetStep = $lastStep
                                break
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
                            Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
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
        try {
            $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
        }
        catch {
            $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ScriptReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $scriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $stepMatches = [regex]::Matches($scriptContent, '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        $totalSteps = $stepMatches.Count

        # Find all step line numbers and names
        $stepLines = @()
        $stepNames = @()
        $lineNumber = 1
        try {
            foreach ($line in (Get-Content -Path $scriptPath -ErrorAction Stop)) {
                if ($line -match '(?i)^\s*New-Step\s+(?:(?:-Name\s+)?(?:"[^"]*"|''[^'']*'')\s+)?\{') {
                    $stepLines += "${scriptPath}:${lineNumber}"
                    if ($line -match '(?i)^\s*New-Step\s+(?:-Name\s+)?(?:"([^"]*)"|''([^'']*)'')') {
                        $stepNames += if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                    } else {
                        $stepNames += $null
                    }
                }
                $lineNumber++
            }
        }
        catch {
            $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ScriptReadFailed',
                [System.Management.Automation.ErrorCategory]::ReadError,
                $scriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        $currentStepNumber = $stepLines.IndexOf($stepId) + 1

        $stepDisplaySuffix = if ($PSCmdlet.ParameterSetName -eq 'Named') { " - '$Name'" } else { '' }
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Executing step $currentStepNumber/$totalSteps$stepDisplaySuffix ($displayStepId)"

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

        # Inject step metadata into $Stepper
        try {
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            if ($stepperData -is [hashtable]) {
                $stepperData['StepName'] = if ($PSCmdlet.ParameterSetName -eq 'Named') { $Name } else { $null }
                $stepperData['StepNumber'] = $currentStepNumber
            }
        } catch {
            # Ignore if unable to inject step metadata
        }

        try {
            & $ScriptBlock

            # Update state file after successful execution (including $Stepper data)
            $stepperData = $callingScope.PSVariable.Get('Stepper').Value
            # Persist state including the script contents for better change inspection
            try {
                $scriptContents = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
            }
            catch {
                $exception = [System.IO.IOException]::new("Failed to read script file '$scriptPath'", $_.Exception)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ScriptReadFailed',
                    [System.Management.Automation.ErrorCategory]::ReadError,
                    $scriptPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $completedStepName = if ($PSCmdlet.ParameterSetName -eq 'Named') { $Name } else { $null }
            Write-StepperState -StatePath $statePath -ScriptHash $currentHash -LastCompletedStep $stepId -StepName $completedStepName -StepNumber $currentStepNumber -StepperData $stepperData -ScriptContents $scriptContents
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Step $currentStepNumber/$totalSteps completed ($displayStepId)"

            if ($stepperData -and $stepperData.Count -gt 0) {
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Saved `$Stepper data ($($stepperData.Count) items)"
            }
        }
        catch {
            $innerMessage = if ($_.Exception.Message) {
                $_.Exception.Message
            } else {
                $_.ToString()
            }
            $exception = [System.Exception]::new("Step failed at ${stepId}: $innerMessage", $_.Exception)
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'StepExecutionFailed',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $stepId
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
