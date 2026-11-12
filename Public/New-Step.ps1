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

        Choosing Start Over is pristine: the state file is deleted, $Stepper is
        removed from the caller's scope, and the previous run's log config is
        discarded, so the new run behaves as if no prior run happened.

        Non-terminating errors never fail a step. When a step emits any, New-Step warns
        with separate counts of surfaced and silenced-or-caught errors, writes full
        details to scriptname.ps1.stepper.errors.log (skipped when logging is off for
        the step), and saves the counts in the state file. A terminating error fails
        the step and ends the script.

        To guarantee "never fail" holds even when the caller set
        $ErrorActionPreference = 'Stop' (CI runners do this globally), New-Step pins
        ErrorActionPreference to Continue in the caller's session state for the
        duration of the step and renders surfaced errors itself. Pass
        -RespectErrorPreference to disable this: the step then runs under the
        caller's preference, and under Stop a non-terminating error fails the step.

    .PARAMETER Name
        Optional name for this step. Displayed in verbose output and resume prompts.

    .PARAMETER ScriptBlock
        The code to execute for this step.

    .PARAMETER RespectErrorPreference
        Runs the step under the caller's $ErrorActionPreference instead of pinning
        it to Continue. With the default (absent), non-terminating errors never
        terminate the step even when the caller set Stop. With this switch, a
        non-terminating error under Stop fails the step and ends the script,
        exactly like a terminating error: state is saved, and the next run offers
        to resume at the failed step.

    .PARAMETER LogPath
        Optional path to a log file. If specified on any step, Stepper uses that path for
        all structured log output and step transcripts for the entire run. If multiple steps
        specify different paths, Stepper prompts the user to choose. If omitted on all steps,
        the log is written to the same directory as the script with the name
        scriptname.ps1.stepper.log.

    .PARAMETER NoLog
        Skips Stepper's transcript and detailed error log for this step when the user
        selects that scope at initialization. Stepper can still display errors in the
        console. Other PowerShell transcripts can still record the step's output.

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
        [switch]$RespectErrorPreference,

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

        [Parameter(DontShow)]
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

    # New-Step performs NO initialization. Start-Stepper owns the entire
    # lifecycle (init, state, resume, log config, script checks) and sets the
    # __StepperInitialized sentinel. Without it, there is nothing to manage.
    $callingScope = $PSCmdlet.SessionState
    $initVar = $callingScope.PSVariable.Get('__StepperInitialized')
    if (-not $initVar -or -not $initVar.Value) {
        $scriptName = Split-Path $scriptPath -Leaf
        $exception = [System.InvalidOperationException]::new("Start-Stepper has not run for $scriptName. Add 'Start-Stepper' inside the first '#region Stepper ignore' block, immediately after the Install-Module guard, before any New-Step call. New-Step no longer initializes Stepper itself.")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StartStepperNotRun',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $scriptPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
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
        $stepLoggingEnabled = $executionState.LoggingEnabled -and
            ($executionState.NoLogStepIds -notcontains $stepId)
        $stepLogPath = if ($stepLoggingEnabled) { $executionState.LogPath } else { $null }

        # Runtime -LogPath conflict check
        if ($LogPath -and $executionState.LogPath -and $LogPath -ne $executionState.LogPath) {
            Write-Warning "New-Step at ${displayStepId}: -LogPath '$LogPath' differs from the resolved log path '$($executionState.LogPath)'. Using resolved path."
        }

        if ($stepLoggingEnabled) {
            Write-StepperLog -Message "Executing step $currentStepNumber/$totalSteps$stepDisplaySuffix ($displayStepId)" -LogPath $stepLogPath
        }

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

        if ($executionState.LoggingEnabled -and $executionState.LogPath -and
            ($executionState.NoLogStepIds -contains $stepId)) {
            Add-Content -Path $executionState.LogPath -Value "=== STEP $currentStepNumber$stepDisplaySuffix LOGGING DISABLED BY USER ==="
        }

        # Check for active transcript once before any retry attempts
        if ($stepLoggingEnabled -and $stepLogPath) {
            # shortcut: This internal property can change; use a public transcript-state API if one is added.
            try {
                $transcriptStateProperty = [System.Management.Automation.Host.PSHostUserInterface].GetProperty(
                    'IsTranscribing', [System.Reflection.BindingFlags]'Instance,NonPublic')
                if ($null -eq $transcriptStateProperty -or $transcriptStateProperty.PropertyType -ne [bool]) {
                    throw 'The internal Boolean IsTranscribing property is unavailable.'
                }
                $isTranscribing = $transcriptStateProperty.GetValue($Host.UI)
            } catch [System.Management.Automation.RuntimeException] {
                throw "Stepper cannot check transcript state. Disable Stepper logging or use a compatible PowerShell version. $($_.Exception.Message)"
            }

            if ($isTranscribing) {
                Write-Host ""
                Write-Host "[!] Stepper detected an active transcript. Stop it or disable Stepper logging, then re-run the script." -ForegroundColor Magenta
                Write-Host ""
                $exception = [System.InvalidOperationException]::new(
                    'An active PowerShell transcript was detected. Stop it with Stop-Transcript or disable Stepper logging, then re-run the script.')
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'TranscriptAlreadyActive',
                    [System.Management.Automation.ErrorCategory]::ResourceBusy,
                    $null
                )
                throw $errorRecord
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

                # Surfaced errors are redirected so they can be counted, then re-emitted.
                # Records absent from $Error (native command stderr) pass through untouched.
                # The step's own Write-Error calls honor the CALLER's $ErrorActionPreference
                # (module functions run in the caller's preference scope). CI sets it to Stop
                # globally, which would turn every surfaced non-terminating error into a step
                # failure. Unless -RespectErrorPreference is given, pin Continue in the
                # caller's session state for the step's duration; restored in finally.
                $callerSessionState = $PSCmdlet.SessionState
                $existingEapVar = $callerSessionState.PSVariable.Get('ErrorActionPreference')
                $savedErrorActionPreference = if ($null -ne $existingEapVar) { $existingEapVar.Value } else { 'Continue' }
                if (-not $RespectErrorPreference.IsPresent) {
                    $callerSessionState.PSVariable.Set('ErrorActionPreference', 'Continue')
                }
                $errorBaseline  = if ($global:Error.Count -gt 0) { $global:Error[0] } else { $null }
                $surfacedErrors = [System.Collections.Generic.List[object]]::new()
                & $ScriptBlock 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord] -and $global:Error.Contains($_)) {
                        $surfacedErrors.Add($_)
                        if ($RespectErrorPreference.IsPresent) {
                            # User opted out of the pin: honor their preference on the
                            # re-emission too. Under Stop this terminates the step.
                            $PSCmdlet.WriteError($_)
                        } else {
                            # The record is already in $Error from the step's own Write-Error.
                            # Re-entering the error pipeline ($PSCmdlet.WriteError) would render
                            # at the outermost caller's preference: under Stop it terminates the
                            # whole script even though the step itself kept running. WriteErrorLine
                            # surfaces it visibly without pipeline semantics, so it can never
                            # escalate to termination.
                            $Host.UI.WriteErrorLine(($_ | Out-String).TrimEnd())
                        }
                    } else {
                        $_
                    }
                }
                $stepErrors = @(Get-StepperErrorDelta -Baseline $errorBaseline)

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

                #Region Non-terminating errors: warn, log details, collect counts for state
                $surfacedCount = $surfacedErrors.Count
                $silencedCount = [Math]::Max(0, $stepErrors.Count - $surfacedCount)
                $stepErrorCounts = @()
                if ($stepErrors.Count -gt 0) {
                    $stepLabel = "Step $currentStepNumber/$totalSteps$stepDisplaySuffix"
                    $countsText = "$surfacedCount surfaced, $silencedCount silenced or caught"
                    $errorLogPath = $null
                    if ($stepLoggingEnabled -and $stepLogPath) {
                        $errorLogPath = Get-StepperErrorLogPath -LogPath $stepLogPath
                        $chronologicalErrors = @($stepErrors)
                        [System.Array]::Reverse($chronologicalErrors)
                        Write-StepperErrorLog -ErrorRecord $chronologicalErrors -LogPath $errorLogPath -StepLabel $stepLabel
                    }
                    $detailsText = if ($errorLogPath) { " Details: $errorLogPath" } else { '' }
                    Write-Warning "$stepLabel completed with non-terminating errors: $countsText.$detailsText"
                    if ($stepLoggingEnabled) {
                        Write-StepperLog -Message "$stepLabel completed with non-terminating errors: $countsText ($displayStepId)" -Level 'WARN' -LogPath $stepLogPath
                    }

                    $stepErrorCounts = @([PSCustomObject]@{
                        StepId     = $stepId
                        StepNumber = $currentStepNumber
                        StepName   = if ($PSCmdlet.ParameterSetName -eq 'Named') { $Name } else { $null }
                        Surfaced   = $surfacedCount
                        Silenced   = $silencedCount
                    })
                }
                $existingErrorCounts = @()
                $priorState = Read-StepperState -StatePath $statePath -ErrorAction SilentlyContinue
                if ($priorState -and $priorState.ErrorCounts) {
                    $existingErrorCounts = @($priorState.ErrorCounts | Where-Object { $_.StepId -ne $stepId })
                }
                #EndRegion Non-terminating errors
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
                    ErrorCounts       = @($existingErrorCounts) + @($stepErrorCounts)
                }
                Write-StepperState @splatState

                $completionMessage = if ($Retry.IsPresent -and $retryAttempt -gt 0) {
                    "Step $currentStepNumber/$totalSteps$stepDisplaySuffix completed in ${elapsed}s (attempt $($retryAttempt + 1), total wall time ${totalElapsed}s) ($displayStepId)"
                } else {
                    "Step $currentStepNumber/$totalSteps$stepDisplaySuffix completed in ${elapsed}s ($displayStepId)"
                }
                if ($stepLoggingEnabled) {
                    Write-StepperLog -Message $completionMessage -LogPath $stepLogPath
                }

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
                    if ($stepLoggingEnabled) {
                        Write-StepperLog -Message "Step $currentStepNumber/$totalSteps$stepDisplaySuffix failed (attempt $($retryAttempt + 1)/$MaxRetries) at $location`: $innerMessage. Retrying in ${waitSeconds}s..." -Level 'WARN' -LogPath $stepLogPath
                    }
                    Write-Host "[>] Retrying in ${waitSeconds}s (attempt $($retryAttempt + 2) of $($MaxRetries + 1))..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $waitSeconds
                    $retryAttempt++
                } else {
                    if ($stepLoggingEnabled) {
                        Write-StepperLog -Message "Step $currentStepNumber/$totalSteps$stepDisplaySuffix FAILED at $location`: $innerMessage" -Level 'ERROR' -LogPath $stepLogPath
                    }

                    $exception = [System.Exception]::new("Step failed [$location]: $innerMessage", $_.Exception)
                    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                        $exception,
                        'StepExecutionFailed',
                        [System.Management.Automation.ErrorCategory]::OperationStopped,
                        $stepId
                    )
                    # throw, not ThrowTerminatingError: that is only statement-terminating
                    # and the script would run on to the next step.
                    throw $errorRecord
                }
            }
            finally {
                if (-not $RespectErrorPreference.IsPresent) {
                    $callerSessionState.PSVariable.Set('ErrorActionPreference', $savedErrorActionPreference)
                }
                if ($tempTranscript -and (Test-Path -LiteralPath $tempTranscript)) {
                    Remove-Item -LiteralPath $tempTranscript -Force -ErrorAction SilentlyContinue
                }
            }
        } while (-not $stepSucceeded)
    }
}
