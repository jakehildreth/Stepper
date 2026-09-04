function Test-StepperScript {
    <#
    .SYNOPSIS
        Validates a script file against Stepper conventions without modifying it.

    .DESCRIPTION
        Inspects the target script and returns a structured result describing any
        issues found. This function NEVER modifies the script file.

        Issue codes and their severities:

          MissingCmdletBinding  (Error)   : [CmdletBinding()] not present
          MissingInstallGuard   (Error)   : Install-Module Stepper guard absent
          MissingCbh            (Warning) : No comment-based help block
          MissingStopStepper    (Warning) : Stop-Stepper not called
          NoSteps               (Warning) : No New-Step blocks found

        IsValid is $true when no Error-severity issues are present (warnings are
        informational and do not affect overall validity).

    .PARAMETER ScriptPath
        Absolute path to the PowerShell script file to inspect.

    .OUTPUTS
        PSCustomObject with properties:
          Path     : Resolved path to the script
          IsValid  : $true when no Error-severity issues exist
          Issues   : Array of PSCustomObjects with Code, Severity, Message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Path')]
        [string]$ScriptPath
    )

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)

    $issues = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Read script content
    $scriptLines = Get-Content -Path $ScriptPath -ErrorAction Stop
    $scriptRaw   = $scriptLines -join [System.Environment]::NewLine

    # Parse via AST
    $parsedAst = Get-ScriptAst -ScriptPath $ScriptPath

    # --- Error: MissingCmdletBinding ---
    $hasCmdletBinding = $parsedAst.Ast.ParamBlock -and
        ($parsedAst.Ast.ParamBlock.Attributes |
            Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })

    if (-not $hasCmdletBinding) {
        $issues.Add((New-StepperIssue -Code 'MissingCmdletBinding' -Severity 'Error' `
            -Message "[CmdletBinding()] is missing. Add it above param() so Stepper can use -WhatIf and common parameters."))
    }

    # --- Error: MissingInstallGuard ---
    $hasInstallGuard = $scriptLines | Where-Object { $_ -match 'Install-Module\s+Stepper' }

    if (-not $hasInstallGuard) {
        $issues.Add((New-StepperIssue -Code 'MissingInstallGuard' -Severity 'Error' `
            -Message "Install-Module Stepper guard is missing. Add it so the script self-installs Stepper when needed."))
    }

    # --- Error: MissingStartStepper ---
    # Start-Stepper owns all initialization and sets the sentinel New-Step
    # requires. A script with New-Step calls but no Start-Stepper fails at the
    # first New-Step. (A script with no New-Step calls does not need it.)
    $blocks = Find-NewStepBlocks -ScriptPath $ScriptPath
    $hasStartStepper = $scriptLines | Where-Object { $_ -match '\b(Start-Stepper|Initialize-Stepper)\b' }

    if ($blocks.NewStepBlocks.Count -gt 0 -and -not $hasStartStepper) {
        $issues.Add((New-StepperIssue -Code 'MissingStartStepper' -Severity 'Error' `
            -Message "Start-Stepper is missing. Add 'Start-Stepper' inside the first '#region Stepper ignore' block, after the Install-Module guard, before any New-Step call."))
    }

    # --- Warning: MissingCbh ---
    $hasCbh = $scriptRaw -match '(?s)<#.*?\.SYNOPSIS.*?#>'

    if (-not $hasCbh) {
        $issues.Add((New-StepperIssue -Code 'MissingCbh' -Severity 'Warning' `
            -Message "No comment-based help found. Add a <# .SYNOPSIS ... #> block for Get-Help support."))
    }

    # --- Warning: MissingStopStepper / NoSteps ---
    if ($blocks.NewStepBlocks.Count -eq 0) {
        $issues.Add((New-StepperIssue -Code 'NoSteps' -Severity 'Warning' `
            -Message "No New-Step blocks found. Stepper scripts should contain at least one New-Step { ... } call."))
    }

    if ($blocks.StopStepperLine -eq -1) {
        $issues.Add((New-StepperIssue -Code 'MissingStopStepper' -Severity 'Warning' `
            -Message "Stop-Stepper is missing. Call Stop-Stepper at the end of the script to mark completion."))
    }

    # IsValid = no Error-severity issues
    $isValid = -not ($issues | Where-Object Severity -EQ 'Error')

    [PSCustomObject]@{
        Path    = $ScriptPath
        IsValid = [bool]$isValid
        Issues  = $issues.ToArray()
    }
}
