function Test-StepperScript {
    <#
    .SYNOPSIS
        Returns canonical structural findings for a Stepper script.

    .DESCRIPTION
        Parses a script through the PowerShell AST and returns located Error and
        Warning findings. This command never modifies the script.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Path')]
        [string]$ScriptPath
    )

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    $scriptContent = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
    $parsedScript = Get-ScriptAst -ScriptPath $ScriptPath -WarningAction SilentlyContinue
    $issues = @(Get-StepperScriptFindings -ScriptPath $ScriptPath -ParsedScript $parsedScript -ScriptContent $scriptContent)

    [PSCustomObject]@{
        Path    = $ScriptPath
        IsValid = [bool](-not ($issues | Where-Object Severity -EQ 'Error'))
        Issues  = $issues
    }
}
