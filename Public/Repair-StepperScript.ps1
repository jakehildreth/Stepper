function Repair-StepperScript {
    <#
    .SYNOPSIS
        Applies safe deterministic additions required by a Stepper script.

    .DESCRIPTION
        Calls Test-StepperScript once to obtain the current canonical findings, then
        delegates planning and the complete write transaction to the shared private
        repair implementation.

        Repair is limited to MissingParamBlock, MissingCmdletBinding,
        MissingInstallGuard, MissingBootstrapRegion, and MissingStartStepper when
        each addition has a safe canonical location. Warnings are never
        automatically repaired.

        A real repair creates one backup, writes once, removes stale Stepper state,
        and returns fresh post-write findings. With -WhatIf, no side effects or
        post-write retest occur and PlannedRepairs describes what would be applied.

    .PARAMETER ScriptPath
        Path to the PowerShell script file to repair.

    .OUTPUTS
        PSCustomObject with Path, IsValid, Issues, Changed, BackupPath,
        AppliedRepairs, and PlannedRepairs.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Path')]
        [string]$ScriptPath
    )

    $preview = [bool]$WhatIfPreference
    $WhatIfPreference = $false

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    $testResult = Test-StepperScript -ScriptPath $resolvedPath
    $repairParameters = @{
        ScriptPath = $resolvedPath
        TestResult = $testResult
        Preview    = $preview
    }

    if ($PSBoundParameters.ContainsKey('Confirm')) {
        $repairParameters.Confirm = [bool]$PSBoundParameters.Confirm
    }

    Invoke-StepperScriptRepair @repairParameters
}
