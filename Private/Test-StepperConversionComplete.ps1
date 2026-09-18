function Test-StepperConversionComplete {
    <#
    .SYNOPSIS
        Returns $true if $StepperConversionComplete = $true appears at script (top) scope.

    .DESCRIPTION
        AST-scans the specified script for a top-level assignment to
        $StepperConversionComplete. Used by the script-integrity lifecycle to
        determine whether conversion review has already been completed.

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
        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst] -or
            $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
            $node.Left.VariablePath.UserPath -ne 'StepperConversionComplete') {
            return $false
        }

        $rightVariables = @($node.Right.FindAll({
            param($rightNode)
            $rightNode -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true))
        return $rightVariables.Count -eq 1 -and
            $rightVariables[0].VariablePath.UserPath -eq 'true' -and
            $node.Right.Extent.Text.Trim() -eq '$true'
    }, $false))  # $false = top-level scope only; does not descend into nested scriptblocks

    return $sentinel.Count -gt 0
}
