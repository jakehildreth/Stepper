function Test-StepperConversionComplete {
    <#
    .SYNOPSIS
        Returns $true if $StepperConversionComplete = $true appears at script (top) scope.

    .DESCRIPTION
        AST-scans the specified script for a top-level assignment to
        $StepperConversionComplete. Used by New-Step's first-run hook to determine
        whether ConvertTo-StepperScript has already been offered for this script.

        The scan is restricted to the top-level script scope
        (searchNestedScriptBlocks = $false) so a sentinel inside a New-Step
        scriptblock body does not satisfy the check.

    .PARAMETER ScriptPath
        Path to the script file to check.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath, [ref]$null, [ref]$null
    )

    $sentinel = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -eq 'StepperConversionComplete'
    }, $false))  # $false = top-level scope only; does not descend into nested scriptblocks

    return $sentinel.Count -gt 0
}
