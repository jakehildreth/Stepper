function Start-Stepper {
    <#
    .SYNOPSIS
        Initializes a Stepper script run before any step or unmanaged code executes.

    .DESCRIPTION
        Start-Stepper owns ALL initialization for a Stepper script. Call it once at
        the top of the script, inside the first '#region Stepper ignore' block,
        immediately after the Install-Module guard.

        It resolves the calling script, initializes the $Stepper hashtable in the
        caller's scope, creates the shared __StepperExecutionState, sets the
        __StepperInitialized sentinel that New-Step requires, reads any existing
        state file, and owns the resume/start-over decision and StepperData
        injection. All of this happens before any unmanaged code runs, so
        resume-aware reads such as 'if (-not $Stepper.ContainsKey(...))' work.

        New-Step throws a terminating error if Start-Stepper has not run, because
        New-Step no longer performs any initialization itself.

        Choosing Start Over is pristine: the state file is deleted, $Stepper is
        recreated empty, and the previous run's log config is discarded, so the new
        run behaves as if no prior run happened.

    .PARAMETER SkipRequirementsCheck
        Suppresses the automatic check for '#requires -Modules Stepper' and
        '[CmdletBinding()]' declarations. Use when you intentionally manage those
        declarations yourself.

    .EXAMPLE
        #region Stepper ignore
        if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }
        Start-Stepper
        #endregion Stepper ignore

        Initializes the run at the top of the script, before any New-Step call or
        unmanaged code.

    .OUTPUTS
        None. Start-Stepper writes $Stepper, __StepperExecutionState, and
        __StepperInitialized into the caller's scope.

    .NOTES
        State files are stored alongside the script with a .stepper extension.
        Alias: Initialize-Stepper.
    #>
    [CmdletBinding()]
    [Alias('Initialize-Stepper')]
    param(
        [Parameter()]
        [switch]$SkipRequirementsCheck
    )

    # Resolve the calling script. Get-StepIdentifier walks the call stack and
    # returns the first frame that is not a Stepper module frame, as "path:line".
    # The line is meaningless for a non-step call; only the path is used.
    try {
        $callerId = Get-StepIdentifier
    }
    catch {
        $exception = [System.InvalidOperationException]::new('Stepper cannot determine the calling script. Ensure Start-Stepper is called from a script file and not from the console or an unsaved file.', $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StepIdentifierNotFound',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $lastColonIndex = $callerId.LastIndexOf(':')
    $scriptPath = $callerId.Substring(0, $lastColonIndex)

    # Guard against unsaved files
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

    $currentHash = Get-ScriptHash -ScriptPath $scriptPath
    $statePath = Get-StepperStatePath -ScriptPath $scriptPath

    $callingScope = $PSCmdlet.SessionState

    # Initialize $Stepper hashtable in calling script scope if it does not exist
    try {
        $existingStepper = $callingScope.PSVariable.Get('Stepper')
        if (-not $existingStepper) {
            $callingScope.PSVariable.Set('Stepper', @{})
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
        }
    }
    catch {
        $callingScope.PSVariable.Set('Stepper', @{})
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Initialized `$Stepper hashtable"
    }

    # Create the shared execution state with fresh-run defaults
    $executionState = @{
        RestoreMode       = $false
        TargetStep        = $null
        CurrentScriptPath = $scriptPath
        CurrentScriptHash = $currentHash
        StatePath         = $statePath
        LogPath           = $null
        LoggingEnabled    = $true
        NoLogStepIds      = @()
    }
    $callingScope.PSVariable.Set('__StepperExecutionState', $executionState)

    # Read any existing state file and own the resume/start-over decision.
    $existingState = Read-StepperState -StatePath $statePath

    if ($existingState) {
        $inventory = Get-StepInventory -ScriptPath $scriptPath
        $stepLines  = $inventory.StepLines
        $stepNames  = $inventory.StepNames
        $totalSteps = $inventory.TotalSteps

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
        $lastStepLine = ($lastStep -split ':')[-1]
        $lastStepDisplay = if ($existingState.LastCompletedStepName) { "$($existingState.LastCompletedStepName) (Step $($lastStepIndex + 1), Line $lastStepLine)" } else { "Step $($lastStepIndex + 1) (Line $lastStepLine)" }

        $hashMismatch = $existingState.ScriptHash -ne $currentHash

        # Persisted $Stepper data is injected ONLY on a Resume choice, never on
        # Start Over. Every Resume path injects (the pre-refactor hash-match
        # top-level Resume path did not; that inconsistency is fixed here).
        $injectStepperData = {
            if ($existingState.StepperData) {
                $callingScope.PSVariable.Set('Stepper', $existingState.StepperData)
                Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Loaded `$Stepper data from disk"
            }
        }
        $startFresh = {
            Write-Host "Starting fresh..." -ForegroundColor Yellow
            $executionState.StartFresh = $true
            Clear-StepperSession -StatePath $statePath -CallingScope $callingScope -ExecutionState $executionState
            # Clear-StepperSession removed $Stepper; recreate it empty so the
            # fresh run starts with a usable, pristine hashtable.
            $callingScope.PSVariable.Set('Stepper', @{})
        }

        if ($hashMismatch) {
            $nextStepId = $stepLines[$lastStepIndex + 1]
            $nextStepLine = ($nextStepId -split ':')[-1]
            $nextStepName = $stepNames[$lastStepIndex + 1]
            $nextStepDisplay = if ($nextStepName) { "$nextStepName (Step $nextStepNumber, Line $nextStepLine)" } else { "Step $nextStepNumber (Line $nextStepLine)" }

            while ($true) {
                if ($executionState.StartFresh -and -not (Test-Path -LiteralPath $statePath)) { break }
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
                Write-Host "  [r] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                Write-Host "  [m] More details" -ForegroundColor White
                Write-Host "  [q] Quit" -ForegroundColor White
                Write-Host ""
                Write-Host "Choice? [" -NoNewline
                Write-Host "r" -NoNewline -ForegroundColor White
                Write-Host "/S" -NoNewline -ForegroundColor Cyan
                Write-Host "/m/q]: " -NoNewline
                $response = Read-StepperChoice -NonInteractiveDefault 's'

                if ($response -eq '' -or $response -eq 'S' -or $response -eq 's') {
                    & $startFresh
                    continue
                }
                elseif ($response -eq 'R' -or $response -eq 'r') {
                    Write-Host ""
                    Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                    $executionState.RestoreMode = $true
                    $executionState.TargetStep = $lastStep
                    & $injectStepperData
                    break
                }
                elseif ($response -eq 'M' -or $response -eq 'm') {
                    Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine -NextStepName $nextStepName -NextStepNumber $nextStepNumber -ShowHashComparison
                    Write-Host "  [r] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                    Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                    Write-Host "  [q] Quit" -ForegroundColor White
                    Write-Host ""
                    Write-Host "Choice? [r/S/q]: " -NoNewline
                    $moreResponse = Read-StepperChoice -NonInteractiveDefault 's'
                    if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                        & $startFresh
                        continue
                    }
                    elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                        Write-Host ""
                        Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                        $executionState.RestoreMode = $true
                        $executionState.TargetStep = $lastStep
                        & $injectStepperData
                        break
                    }
                    elseif ($moreResponse -eq 'Q' -or $moreResponse -eq 'q') {
                        Write-Host ""
                        Write-Host "Exiting..." -ForegroundColor Yellow
                        exit
                    }
                    else {
                        & $startFresh
                        continue
                    }
                }
                elseif ($response -eq 'Q' -or $response -eq 'q') {
                    Write-Host ""
                    Write-Host "Exiting..." -ForegroundColor Yellow
                    exit
                }
                else {
                    & $startFresh
                    continue
                }
            }
        }
        else {
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
                $nextStepId = $stepLines[$lastStepIndex + 1]
                $nextStepLine = ($nextStepId -split ':')[-1]
                $nextStepName = $stepNames[$lastStepIndex + 1]
                $nextStepDisplay = if ($nextStepName) { "$nextStepName (Step $nextStepNumber, Line $nextStepLine)" } else { "Step $nextStepNumber (Line $nextStepLine)" }

                while ($true) {
                    if ($executionState.StartFresh -and -not (Test-Path -LiteralPath $statePath)) { break }
                    Write-Host "How would you like to proceed?"
                    Write-Host ""
                    Write-Host "  [R] Resume $scriptName from $nextStepDisplay (Default)" -ForegroundColor Cyan
                    Write-Host "  [s] Start over" -ForegroundColor White
                    Write-Host "  [m] More details" -ForegroundColor White
                    Write-Host "  [q] Quit" -ForegroundColor White
                    Write-Host ""
                    Write-Host "Choice? [" -NoNewline
                    Write-Host "R" -NoNewline -ForegroundColor Cyan
                    Write-Host "/s/m/q]: " -NoNewline
                    $response = Read-StepperChoice -NonInteractiveDefault 'r'

                    if ($response -eq '' -or $response -eq 'R' -or $response -eq 'r') {
                        Write-Host ""
                        Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                        $executionState.RestoreMode = $true
                        $executionState.TargetStep = $lastStep
                        & $injectStepperData
                        break
                    }
                    elseif ($response -eq 'S' -or $response -eq 's') {
                        & $startFresh
                        continue
                    }
                    elseif ($response -eq 'M' -or $response -eq 'm') {
                        Show-MoreDetails -ExistingState $existingState -ScriptPath $scriptPath -CurrentHash $currentHash -LastStep $lastStep -NextStepLine $nextStepLine -NextStepName $nextStepName -NextStepNumber $nextStepNumber
                        Write-Host "  [R] Resume $scriptName from $nextStepDisplay (Default)" -ForegroundColor Cyan
                        Write-Host "  [S] Start over" -ForegroundColor White
                        Write-Host "  [Q] Quit" -ForegroundColor White
                        Write-Host ""
                        Write-Host "Choice? [R/s/q]: " -NoNewline
                        $moreResponse = Read-StepperChoice -NonInteractiveDefault 'r'
                        if ($moreResponse -eq '' -or $moreResponse -eq 'S' -or $moreResponse -eq 's') {
                            & $startFresh
                            continue
                        }
                        elseif ($moreResponse -eq 'R' -or $moreResponse -eq 'r') {
                            Write-Host ""
                            Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                            $executionState.RestoreMode = $true
                            $executionState.TargetStep = $lastStep
                            & $injectStepperData
                            break
                        }
                        elseif ($moreResponse -eq 'Q' -or $moreResponse -eq 'q') {
                            Write-Host ""
                            Write-Host "Exiting..." -ForegroundColor Yellow
                            exit
                        }
                        else {
                            & $startFresh
                            continue
                        }
                    }
                    elseif ($response -eq 'Q' -or $response -eq 'q') {
                        Write-Host ""
                        Write-Host "Exiting..." -ForegroundColor Yellow
                        exit
                    }
                    else {
                        Write-Host ""
                        Write-Host "Resuming from $nextStepDisplay..." -ForegroundColor Green
                        $executionState.RestoreMode = $true
                        $executionState.TargetStep = $lastStep
                        & $injectStepperData
                        break
                    }
                }
            }
            else {
                Write-Host "All steps were completed. Starting fresh..." -ForegroundColor Yellow
                & $startFresh
            }
            Write-Host ""
        }
    }

    #Region Log config: runs AFTER the resume decision so it sees the real
    # StartFresh flag. Resume restores from state; fresh/Start-Over resolves anew.
    if ($existingState -and $existingState.LogPath -and -not $executionState.StartFresh) {
        # Resumed run: restore log config from state, no prompts
        $executionState.LogPath        = $existingState.LogPath
        $executionState.LoggingEnabled = $existingState.LoggingEnabled
        $executionState.NoLogStepIds   = if ($existingState.NoLogStepIds) { @($existingState.NoLogStepIds) } else { @() }
    }
    else {
        # Fresh run (or Start Over): scan AST and resolve
        $logConfig  = Get-StepLogConfig -ScriptPath $scriptPath
        $scriptDir  = Split-Path -Path $scriptPath -Parent
        $scriptName = Split-Path -Path $scriptPath -Leaf
        $defaultLog = Join-Path -Path $scriptDir -ChildPath "$scriptName.stepper.log"

        # Resolve log path
        if ($logConfig.HasConflict) {
            Write-Host ""
            Write-Host "[i] Multiple -LogPath values found across New-Step calls:" -ForegroundColor Cyan
            Write-Host ""
            $pathChoices = $logConfig.UniqueStaticLogPaths
            for ($pi = 0; $pi -lt $pathChoices.Count; $pi++) {
                Write-Host "  [$($pi + 1)] $($pathChoices[$pi])" -ForegroundColor White
            }
            Write-Host ""
            Write-Host "Which log path should be used? [1-$($pathChoices.Count)] (default: 1): " -NoNewline
            $pathChoice = Read-StepperChoice -NonInteractiveDefault '1'
            $choiceIndex = 0
            if (-not [int]::TryParse($pathChoice, [ref]$choiceIndex) -or
                $choiceIndex -lt 1 -or $choiceIndex -gt $pathChoices.Count) {
                $choiceIndex = 1
            }
            $resolvedLogPath = $pathChoices[$choiceIndex - 1]
        }
        elseif ($logConfig.UniqueStaticLogPaths.Count -eq 1) {
            $resolvedLogPath = $logConfig.UniqueStaticLogPaths[0]
        }
        else {
            $resolvedLogPath = $defaultLog
        }

        # Validate parent directory
        $logDir = Split-Path -Path $resolvedLogPath -Parent
        if ($logDir -and -not (Test-Path -LiteralPath $logDir -PathType Container)) {
            $exception = [System.IO.DirectoryNotFoundException]::new(
                "Log file directory does not exist: '$logDir'. Create the directory or omit -LogPath to use the default location.")
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'LogPathDirectoryNotFound',
                [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
                $resolvedLogPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        # Resolve NoLog scope
        $loggingEnabled = $true
        $noLogIds       = @()

        if ($logConfig.NoLogStepIds.Count -gt 0) {
            $noLogList = ($logConfig.NoLogStepIds | ForEach-Object {
                $parts = $_ -split ':'
                "$([System.IO.Path]::GetFileName($parts[0])):$($parts[-1])"
            }) -join ', '

            Write-Host ""
            Write-Host "[i] Some steps have -NoLog specified: $noLogList" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  [A] Log all steps, ignore -NoLog flags (Default)" -ForegroundColor Cyan
            Write-Host "  [s] Skip logging for those steps only" -ForegroundColor White
            Write-Host "  [d] Disable logging entirely" -ForegroundColor White
            Write-Host "  [q] Quit" -ForegroundColor White
            Write-Host ""
            Write-Host "Choice? [" -NoNewline
            Write-Host "A" -NoNewline -ForegroundColor Cyan
            Write-Host "/s/d/q]: " -NoNewline
            $noLogChoice = Read-StepperChoice -NonInteractiveDefault 'a'

            switch ($noLogChoice.ToLower()) {
                's' {
                    $noLogIds = @($logConfig.NoLogStepIds)
                }
                'd' {
                    $loggingEnabled = $false
                }
                'q' {
                    Write-Host ""
                    Write-Host "Exiting..." -ForegroundColor Yellow
                    exit
                }
                default {
                    # 'a' or anything else: log everything
                }
            }
        }

        $executionState.LogPath        = $resolvedLogPath
        $executionState.LoggingEnabled = $loggingEnabled
        $executionState.NoLogStepIds   = $noLogIds
    }
    #EndRegion Log config

    # Set the sentinel New-Step requires. Done last so a partial init never
    # leaves the sentinel set.
    $callingScope.PSVariable.Set('__StepperInitialized', $true)
}
