function Get-StepperInitInsertionIndex {
    <#
    .SYNOPSIS
        Finds the line index where the $Stepper initializer should be inserted.

    .DESCRIPTION
        Returns the 0-based line index (into the array of script lines) at which the
        idempotent $Stepper initializer should be inserted.

        Preferred placement is inside the first '#region Stepper ignore' block,
        immediately before its '#endregion' line. The unmanaged-code scanner ignores
        lines inside these regions, so an initializer placed there is not flagged as
        a new unmanaged-code block on the next run. When no ignore region exists, the
        initializer goes immediately after the param() block (or before the first
        statement when there is no param block).

        Shared by ConvertTo-StepperScript and Repair-StepperScript so both insert the
        initializer in the same place.

    .PARAMETER ScriptPath
        Path to the script file to analyze.

    .OUTPUTS
        System.Int32 - 0-based insertion line index.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $scriptLines = Get-Content -Path $ScriptPath -ErrorAction Stop

    # Prefer inside the first '#region Stepper ignore' block, before its '#endregion'.
    # The scanner only ignores lines within a region/endregion pair.
    for ($i = 0; $i -lt $scriptLines.Count; $i++) {
        if ($scriptLines[$i] -match '^\s*#region\s+Stepper\s+ignore') {
            # Find the matching #endregion and insert just before it
            for ($j = $i + 1; $j -lt $scriptLines.Count; $j++) {
                if ($scriptLines[$j] -match '^\s*#endregion\s+Stepper\s+ignore') {
                    return $j
                }
            }
            # Region opened but never closed; fall through to param-based placement
            break
        }
    }

    $parsedAst = Get-ScriptAst -ScriptPath $ScriptPath

    if ($parsedAst.Ast.ParamBlock) {
        # Insert on the line immediately after the param() block's closing line
        return $parsedAst.Ast.ParamBlock.Extent.EndLineNumber
    }

    # No param block: insert before the first top-level statement
    $firstStatement = @($parsedAst.Ast.EndBlock.Statements) | Select-Object -First 1
    if ($firstStatement) {
        return $firstStatement.Extent.StartLineNumber - 1
    }

    return 0
}
