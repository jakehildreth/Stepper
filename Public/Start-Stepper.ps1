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

    # Set the sentinel New-Step requires. Done last so a partial init never
    # leaves the sentinel set.
    $callingScope.PSVariable.Set('__StepperInitialized', $true)
}
