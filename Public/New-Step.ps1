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

    .PARAMETER LogPath
        Optional path to a log file. If specified on any step, Stepper uses that path for
        all structured log output and step transcripts for the entire run. If multiple steps
        specify different paths, Stepper prompts the user to choose. If omitted on all steps,
        the log is written to the same directory as the script with the name
        scriptname.ps1.stepper.log.

    .PARAMETER NoLog
        Skips logging for this step. When present on one or more steps, Stepper prompts the
        user at init time to choose whether to ignore the flag (log all steps), skip only
        the flagged steps, or disable logging entirely.

    .PARAMETER Retry
        Enables exponential backoff retry behavior for this step. When specified, a failed
        ScriptBlock will be retried up to -MaxRetries times before the step is considered
        failed.

    .PARAMETER RetryInterval
        Base interval in seconds between retry attempts. Each subsequent retry waits
        RetryInterval * 2^attempt seconds. Defaults to 60. Requires -Retry. Minimum value: 1.

    .PARAMETER MaxRetries
        Maximum number of retry attempts after the initial failure. A value of 5 means the
        ScriptBlock may execute up to 6 times total (1 initial + 5 retries). Defaults to 5.
        Requires -Retry. Minimum value: 1.

    .PARAMETER SkipRequirementsCheck
        Suppresses the automatic check for '#requires -Modules Stepper' and '[CmdletBinding()]'
        declarations. Use when you intentionally manage those declarations yourself.

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
            Write-Host "Unnamed step. Backward-compatible syntax."
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
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [switch]$NoLog,

        [Parameter()]
        [switch]$Retry,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$RetryInterval = 60,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRetries = 5,

        [Parameter()]
        [switch]$SkipRequirementsCheck
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
            LogPath           = $null
            LoggingEnabled    = $true
            NoLogStepIds      = @()
        }
        $callingScope.PSVariable.Set('__StepperExecutionState', $executionState)

        # Check script requirements (declarations) first
        if (-not $SkipRequirementsCheck.IsPresent) {
            $preRepairResult = Test-StepperScript -ScriptPath $scriptPath
            $needsRestart    = $preRepairResult.Issues |
                Where-Object { $_.Code -in 'MissingCmdletBinding', 'MissingInstallGuard' }
            Repair-StepperScript -ScriptPath $scriptPath -WarningAction SilentlyContinue | Out-Null
            if ($needsRestart) {
                $scriptName = Split-Path $scriptPath -Leaf
                $added = ($needsRestart | ForEach-Object {
                    switch ($_.Code) {
                        'MissingCmdletBinding' { '[CmdletBinding()]' }
                        'MissingInstallGuard'  { 'Install-Module guard' }
                    }
                }) -join ' and '
                Write-Host ""
                Write-Host "$added has been added to $scriptName." -ForegroundColor Green
                Write-Host "Please re-run $scriptName." -ForegroundColor Green
                exit
            }
        }

        # Check for unmanaged code between New-Step blocks and before Stop-Stepper
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

        $blockInfo = Find-NewStepBlocks -ScriptPath $scriptPath
        $newStepBlocks = $blockInfo.NewStepBlocks
        $stopStepperLine = $blockInfo.StopStepperLine

        $unmanagedBlocks = Find-UnmanagedCodeBlocks -ScriptLines $scriptLines -NewStepBlocks $newStepBlocks -StopStepperLine $stopStepperLine

        # Process each unmanaged block individually
        if ($unmanagedBlocks.Count -gt 0) {
            $scriptName = Split-Path $scriptPath -Leaf
            $allLinesToRemove = @{}

            foreach ($block in $unmanagedBlocks) {
                $action = Get-UnmanagedCodeAction -ScriptName $scriptName -ScriptLines $scriptLines -Block $block

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
                Update-ScriptWithUnmanagedActions -ScriptPath $scriptPath -ScriptLines $scriptLines -Actions $allLinesToRemove -NewStepBlocks $newStepBlocks
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
            Write-Host "  [c] Continue without Stop-Stepper" -ForegroundColor White
            Write-Host "  [q] Quit" -ForegroundColor White
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
                    New-StepperBackup -Path $scriptPath | Out-Null
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
                    New-StepperBackup -Path $scriptPath | Out-Null
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

        # Offer ConvertTo-StepperScript once on first run if script has not been converted
        if (-not (Test-StepperConversionComplete -ScriptPath $scriptPath)) {
            $conversionCandidates = @(Find-CrossStepVariables -ScriptPath $scriptPath)
            if ($conversionCandidates.Count -gt 0) {
                ConvertTo-StepperScript -Path $scriptPath
                if (Test-StepperConversionComplete -ScriptPath $scriptPath) {
                    # Script was rewritten; tell user what happened and exit
                    $scriptName = Split-Path $scriptPath -Leaf
                    Write-Host ""
                    Write-Host "Cross-step variables have been converted to `$Stepper.<Var> notation and `$StepperConversionComplete = `$true has been added to $scriptName." -ForegroundColor Green
                    Write-Host "Please re-run $scriptName." -ForegroundColor Green
                    exit
                }
            }
        }

        $existingState = Read-StepperState -StatePath $statePath

        #Region Log config: resolve on fresh run, restore on resume
        if ($existingState -and $existingState.LogPath) {
            # Resumed run: restore log config from state, no prompts
            $executionState.LogPath        = $existingState.LogPath
            $executionState.LoggingEnabled = $existingState.LoggingEnabled
            $executionState.NoLogStepIds   = if ($existingState.NoLogStepIds) { @($existingState.NoLogStepIds) } else { @() }
        } else {
            # Fresh run: scan AST and resolve
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
                try {
                    $pathChoice = Read-Host
                } catch {
                    $pathChoice = '1'
                    Write-Warning "[Stepper] Non-interactive context detected, defaulting to first log path."
                }
                $choiceIndex = 0
                if (-not [int]::TryParse($pathChoice, [ref]$choiceIndex) -or
                    $choiceIndex -lt 1 -or $choiceIndex -gt $pathChoices.Count) {
                    $choiceIndex = 1
                }
                $resolvedLogPath = $pathChoices[$choiceIndex - 1]
            } elseif ($logConfig.UniqueStaticLogPaths.Count -eq 1) {
                $resolvedLogPath = $logConfig.UniqueStaticLogPaths[0]
            } else {
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
                try {
                    $noLogChoice = Read-Host
                } catch {
                    $noLogChoice = 'a'
                    Write-Warning "[Stepper] Non-interactive context detected, defaulting to log all steps."
                }

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
                # Script has been modified since last run; prompt user for action
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
                    Write-Host "  [r] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                    Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                    Write-Host "  [m] More details" -ForegroundColor White
                    Write-Host "  [q] Quit" -ForegroundColor White
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
                        Write-Host "  [r] Resume $scriptName from $nextStepDisplay (May produce inconsistent results)" -ForegroundColor White
                        Write-Host "  [S] Start over (Default)" -ForegroundColor Cyan
                        Write-Host "  [q] Quit" -ForegroundColor White
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
                $inventory = Get-StepInventory -ScriptPath $scriptPath
                $stepLines  = $inventory.StepLines
                $stepNames  = $inventory.StepNames
                $totalSteps = $inventory.TotalSteps

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
                        Write-Host "  [s] Start over" -ForegroundColor White
                        Write-Host "  [m] More details" -ForegroundColor White
                        Write-Host "  [q] Quit" -ForegroundColor White
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
        $skipReason = $null

        # In restore mode: skip steps until we reach the target
        if ($stepId -eq $executionState.TargetStep) {
            # This is the last completed step, skip it and disable restore mode
            $executionState.RestoreMode = $false
            $shouldExecute = $false
            $skipReason = 'last completed step'
        }
        elseif ($executionState.RestoreMode) {
            # Still skipping
            $shouldExecute = $false
            $skipReason = 'previously completed'
        }

        if ($skipReason -and $executionState.LoggingEnabled -and $executionState.LogPath -and
            ($executionState.NoLogStepIds -notcontains $stepId)) {
            $skipInventory = Get-StepInventory -ScriptPath $scriptPath
            $skipNumber    = $skipInventory.StepLines.IndexOf($stepId) + 1
            $skipTotal     = $skipInventory.TotalSteps
            $skipNamePart  = if ($PSCmdlet.ParameterSetName -eq 'Named') { " ('$Name')" } else { '' }
            Write-StepperLog -Message "Skipping step $skipNumber/$skipTotal$skipNamePart because it already completed in a previous run. ($displayStepId)" -LogPath $executionState.LogPath
        }
    }

    # Execute the step if needed
    if ($shouldExecute) {
        # Format step identifier for display (scriptname:line instead of full path)
        $stepIdParts = $stepId -split ':'
        $scriptName = Split-Path $stepIdParts[0] -Leaf
        $displayStepId = "${scriptName}:$($stepIdParts[1])"

        # Calculate step number (X/Y)
        $inventory = Get-StepInventory -ScriptPath $scriptPath
        $stepLines  = $inventory.StepLines
        $stepNames  = $inventory.StepNames
        $totalSteps = $inventory.TotalSteps
        $currentStepNumber = $stepLines.IndexOf($stepId) + 1

        $stepDisplaySuffix = if ($PSCmdlet.ParameterSetName -eq 'Named') { " - '$Name'" } else { '' }

        # Resolve logging state for this step
        $stepLogPath = $executionState.LogPath
        $stepLoggingEnabled = $executionState.LoggingEnabled -and
            ($executionState.NoLogStepIds -notcontains $stepId)

        # Runtime -LogPath conflict check
        if ($LogPath -and $stepLogPath -and $LogPath -ne $stepLogPath) {
            Write-Warning "New-Step at ${displayStepId}: -LogPath '$LogPath' differs from the resolved log path '$stepLogPath'. Using resolved path."
        }

        Write-StepperLog -Message "Executing step $currentStepNumber/$totalSteps$stepDisplaySuffix ($displayStepId)" -LogPath $stepLogPath

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

        # Warn if retry-related params are specified without -Retry
        if (-not $Retry.IsPresent) {
            if ($PSBoundParameters.ContainsKey('RetryInterval')) {
                Write-Warning "New-Step at ${displayStepId}: -RetryInterval has no effect without -Retry."
            }
            if ($PSBoundParameters.ContainsKey('MaxRetries')) {
                Write-Warning "New-Step at ${displayStepId}: -MaxRetries has no effect without -Retry."
            }
        }

        if (-not $stepLoggingEnabled -and $stepLogPath) {
            Add-Content -Path $stepLogPath -Value "=== STEP $currentStepNumber$stepDisplaySuffix LOGGING DISABLED BY USER ==="
        }

        # Check for active transcript once before any retry attempts
        if ($stepLoggingEnabled -and $stepLogPath) {
            if ($Host.UI.IsTranscribing) {
                Write-Host ""
                Write-Host "[!] Stepper detected an active transcript. Stop your transcript with Stop-Transcript and re-run the script." -ForegroundColor Magenta
                Write-Host ""
                $exception = [System.InvalidOperationException]::new(
                    'An active PowerShell transcript was detected. Stop the transcript with Stop-Transcript and re-run the script.')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'TranscriptAlreadyActive',
                    [System.Management.Automation.ErrorCategory]::ResourceBusy,
                    $null
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
        }

        $retryAttempt   = 0
        $stepSucceeded  = $false
        $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        do {
            $transcriptStarted = $false
            $tempTranscript    = $null

            if ($stepLoggingEnabled -and $stepLogPath) {
                $tempTranscript = [System.IO.Path]::GetTempFileName()
                Start-Transcript -Path $tempTranscript -Force -UseMinimalHeader -IncludeInvocationHeader | Out-Null
                $transcriptStarted = $true
            }

            try {
                $attemptStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                & $ScriptBlock
                $attemptStopwatch.Stop()
                $totalStopwatch.Stop()
                $elapsed      = [Math]::Round($attemptStopwatch.Elapsed.TotalSeconds, 2)
                $totalElapsed = [Math]::Round($totalStopwatch.Elapsed.TotalSeconds, 2)

                if ($transcriptStarted) {
                    Stop-Transcript | Out-Null
                    $transcriptStarted = $false
                    $transcriptContent = Get-Content -Path $tempTranscript -Raw -ErrorAction SilentlyContinue
                    Add-Content -Path $stepLogPath -Value "=== BEGIN STEP $currentStepNumber$stepDisplaySuffix TRANSCRIPT ==="
                    Add-Content -Path $stepLogPath -Value $transcriptContent
                    Add-Content -Path $stepLogPath -Value "=== END STEP $currentStepNumber$stepDisplaySuffix TRANSCRIPT ==="
                }

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
                $splatState = @{
                    StatePath         = $statePath
                    ScriptHash        = $currentHash
                    LastCompletedStep = $stepId
                    StepName          = $completedStepName
                    StepNumber        = $currentStepNumber
                    StepperData       = $stepperData
                    ScriptContents    = $scriptContents
                    LogPath           = $executionState.LogPath
                    LoggingEnabled    = if ($executionState.LoggingEnabled -is [bool]) { $executionState.LoggingEnabled } else { $true }
                    NoLogStepIds      = $executionState.NoLogStepIds
                }
                Write-StepperState @splatState

                $completionMessage = if ($Retry.IsPresent -and $retryAttempt -gt 0) {
                    "Step $currentStepNumber/$totalSteps$stepDisplaySuffix completed in ${elapsed}s (attempt $($retryAttempt + 1), total wall time ${totalElapsed}s) ($displayStepId)"
                } else {
                    "Step $currentStepNumber/$totalSteps$stepDisplaySuffix completed in ${elapsed}s ($displayStepId)"
                }
                Write-StepperLog -Message $completionMessage -LogPath $stepLogPath

                if ($stepperData -and $stepperData.Count -gt 0) {
                    Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Saved `$Stepper data ($($stepperData.Count) items)"
                }

                $stepSucceeded = $true
            }
            catch {
                if ($transcriptStarted) {
                    Stop-Transcript | Out-Null
                    $transcriptStarted = $false
                    $partialContent = Get-Content -Path $tempTranscript -Raw -ErrorAction SilentlyContinue
                    if ($stepLogPath) {
                        $attemptLabel = if ($Retry.IsPresent) { " [ATTEMPT $($retryAttempt + 1) PARTIAL]" } else { ' [PARTIAL]' }
                        Add-Content -Path $stepLogPath -Value "=== BEGIN STEP $currentStepNumber$stepDisplaySuffix TRANSCRIPT$attemptLabel ==="
                        Add-Content -Path $stepLogPath -Value $partialContent
                        Add-Content -Path $stepLogPath -Value "=== END STEP $currentStepNumber$stepDisplaySuffix TRANSCRIPT$attemptLabel ==="
                    }
                }

                $innerMessage = if ($_.Exception.Message) {
                    $_.Exception.Message
                } else {
                    $_.ToString()
                }
                $origin = $_.InvocationInfo
                $location = if ($origin.ScriptName -and $origin.ScriptLineNumber) {
                    "$([System.IO.Path]::GetFileName($origin.ScriptName)):$($origin.ScriptLineNumber)"
                } else { $stepId }

                if ($Retry.IsPresent -and $retryAttempt -lt $MaxRetries) {
                    $waitSeconds = [int]($RetryInterval * [Math]::Pow(2, $retryAttempt))
                    Write-StepperLog -Message "Step $currentStepNumber/$totalSteps$stepDisplaySuffix failed (attempt $($retryAttempt + 1)/$MaxRetries) at $location`: $innerMessage. Retrying in ${waitSeconds}s..." -Level 'WARN' -LogPath $stepLogPath
                    Write-Host "[>] Retrying in ${waitSeconds}s (attempt $($retryAttempt + 2) of $($MaxRetries + 1))..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $waitSeconds
                    $retryAttempt++
                } else {
                    Write-StepperLog -Message "Step $currentStepNumber/$totalSteps$stepDisplaySuffix FAILED at $location`: $innerMessage" -Level 'ERROR' -LogPath $stepLogPath

                    $exception = [System.Exception]::new("Step failed [$location]: $innerMessage", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'StepExecutionFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        $stepId
                    )
                    $PSCmdlet.ThrowTerminatingError($errorRecord)
                }
            }
            finally {
                if ($tempTranscript -and (Test-Path -LiteralPath $tempTranscript)) {
                    Remove-Item -LiteralPath $tempTranscript -Force -ErrorAction SilentlyContinue
                }
            }
        } while (-not $stepSucceeded)
    }
}
