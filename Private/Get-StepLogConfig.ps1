function Get-StepLogConfig {
    <#
    .SYNOPSIS
        Scans a script's AST for -LogPath and -NoLog parameters on New-Step calls.

    .DESCRIPTION
        Uses the cached PowerShell AST (via Get-ScriptAst) to find all New-Step CommandAst
        nodes that appear before Stop-Stepper. For each call, inspects CommandElements to
        detect:
          - A -LogPath parameter: if the argument is a static string, records its value;
            otherwise records '<dynamic>' for variable or expression arguments.
          - A -NoLog switch: records the step identifier (ScriptPath:LineNumber) for
            any step that carries this switch.

        Returns a PSCustomObject summarising the unique static log paths found (with a
        conflict flag when two or more differ) and the list of -NoLog step identifiers.

    .PARAMETER ScriptPath
        Absolute path to the script file to analyse.

    .OUTPUTS
        PSCustomObject with properties:
          UniqueStaticLogPaths  — string[] of distinct resolved -LogPath values (may include '<dynamic>')
          HasConflict           — bool; $true when UniqueStaticLogPaths.Count -gt 1
          NoLogStepIds          — string[] of "ScriptPath:LineNumber" for -NoLog steps
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $parsed = Get-ScriptAst -ScriptPath $ScriptPath
    $ast = $parsed.Ast

    # Find Stop-Stepper cutoff line
    $stopCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'Stop-Stepper'
    }, $true)

    $stopLine = if ($stopCalls -and $stopCalls.Count -gt 0) {
        ($stopCalls | Sort-Object { $_.Extent.StartLineNumber })[0].Extent.StartLineNumber
    } else {
        [int]::MaxValue
    }

    # Find all New-Step calls before Stop-Stepper
    $newStepCalls = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.CommandAst] -and
        $args[0].GetCommandName() -eq 'New-Step'
    }, $true) | Where-Object { $_.Extent.StartLineNumber -lt $stopLine } |
        Sort-Object { $_.Extent.StartLineNumber }

    $logPaths = [System.Collections.Generic.List[string]]::new()
    $noLogIds = [System.Collections.Generic.List[string]]::new()

    foreach ($call in $newStepCalls) {
        $stepLine = $call.Extent.StartLineNumber
        $stepId = "${ScriptPath}:${stepLine}"
        $elements = $call.CommandElements

        for ($i = 1; $i -lt $elements.Count; $i++) {
            $el = $elements[$i]

            if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                $paramName = $el.ParameterName

                if ($paramName -eq 'LogPath') {
                    # Next element is the argument
                    $nextIndex = $i + 1
                    if ($nextIndex -lt $elements.Count) {
                        $arg = $elements[$nextIndex]
                        if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                            $arg -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
                            $logPaths.Add($arg.Value)
                        } else {
                            # Variable, expression, or other non-static value
                            $logPaths.Add('<dynamic>')
                        }
                        $i++  # Skip the argument element
                    }
                } elseif ($paramName -eq 'NoLog') {
                    $noLogIds.Add($stepId)
                }
            }
        }
    }

    $uniquePaths = @($logPaths | Select-Object -Unique)

    return [PSCustomObject]@{
        UniqueStaticLogPaths = $uniquePaths
        HasConflict          = ($uniquePaths.Count -gt 1)
        NoLogStepIds         = @($noLogIds)
    }
}
