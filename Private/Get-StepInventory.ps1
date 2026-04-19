function Get-StepInventory {
    <#
    .SYNOPSIS
        Returns an inventory of all New-Step calls in a script file.

    .DESCRIPTION
        Uses the PowerShell AST via Get-ScriptAst to locate every New-Step CommandAst node,
        collecting the step identifier string (path:line) and step name for each. Steps that
        appear after Stop-Stepper are excluded, matching runtime behavior.

    .PARAMETER ScriptPath
        Absolute path to the script file to analyze.

    .OUTPUTS
        PSCustomObject with properties:
          StepLines  — string[] of "$ScriptPath:$lineNumber" (1-based), one per step
          StepNames  — string[] (or $null entries) of step names in the same order
          TotalSteps — int count of steps

    .NOTES
        StepLines format matches Get-StepIdentifier output so callers can use IndexOf() to
        locate the current or last-completed step.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $parsed = Get-ScriptAst -ScriptPath $ScriptPath
    $ast = $parsed.Ast

    # Find Stop-Stepper to determine the cutoff line
    $stopCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'Stop-Stepper'
    }, $true)

    $stopLine = if ($stopCalls -and $stopCalls.Count -gt 0) {
        ($stopCalls | Sort-Object { $_.Extent.StartLineNumber })[0].Extent.StartLineNumber
    } else {
        [int]::MaxValue
    }

    $stepLines = @()
    $stepNames = @()

    $newStepCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'New-Step'
    }, $true) | Sort-Object { $_.Extent.StartLineNumber }

    foreach ($call in $newStepCalls) {
        $callLine = $call.Extent.StartLineNumber

        # Exclude steps after Stop-Stepper
        if ($callLine -ge $stopLine) {
            continue
        }

        $stepLines += "${ScriptPath}:${callLine}"

        # Extract step name from CommandElements.
        # CommandElements[0] is always the command name itself (a StringConstantExpressionAst).
        # Skip index 0, CommandParameterAst (-Name), and ScriptBlockExpressionAst (the body).
        # The first remaining element is the step name argument.
        $nameElement = $null
        $elementIndex = 0
        foreach ($element in $call.CommandElements) {
            if ($elementIndex -eq 0) { $elementIndex++; continue }
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) { $elementIndex++; continue }
            if ($element -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) { $elementIndex++; continue }
            $nameElement = $element
            break
        }

        if ($nameElement -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $nameElement -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            $stepNames += $nameElement.Value
        } else {
            $stepNames += $null
        }
    }

    return [PSCustomObject]@{
        StepLines  = $stepLines
        StepNames  = $stepNames
        TotalSteps = $stepLines.Count
    }
}
