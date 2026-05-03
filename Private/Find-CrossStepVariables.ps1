function Find-CrossStepVariables {
    <#
    .SYNOPSIS
        Finds variables that are written in one New-Step block and read in a later one.

    .DESCRIPTION
        AST-walks all New-Step scriptblock bodies in a script. Returns variable names
        that are assigned (written) in at least one step and referenced (read) in a
        different, later step.

        Excludes:
        - Variables already accessed via $Stepper.* member notation
        - PowerShell automatic variables ($_, $Error, $PSScriptRoot, etc.)

        This function is used by ConvertTo-StepperScript to identify candidates for
        $Stepper.<var> conversion.

    .PARAMETER ScriptPath
        Path to the script file to analyze.

    .PARAMETER ScriptContent
        Raw script content as a string. Used by tests to avoid temp files.

    .OUTPUTS
        System.String[] - Variable names (without leading $) that cross step boundaries.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(ParameterSetName = 'Content', Mandatory)]
        [AllowEmptyString()]
        [string]$ScriptContent
    )

    $automaticVars = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($v in @(
        '_', 'PSItem', 'Error', 'null', 'true', 'false',
        'PSVersionTable', 'Host', 'profile', 'args', 'input',
        'MyInvocation', 'PSCmdlet', 'PSBoundParameters',
        'PSDefaultParameterValues', 'PSScriptRoot', 'PSCommandPath',
        'ExecutionContext', 'ConfirmPreference', 'DebugPreference',
        'ErrorActionPreference', 'VerbosePreference', 'WarningPreference',
        'InformationPreference', 'WhatIfPreference', 'ProgressPreference',
        'PSStyle'
    )) {
        [void]$automaticVars.Add($v)
    }

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        $parsed = Get-ScriptAst -ScriptPath $ScriptPath
        $ast = $parsed.Ast
    } else {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $ScriptContent, [ref]$tokens, [ref]$errors
        )
    }

    # Collect all New-Step CommandAst nodes in document order
    $newStepCalls = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'New-Step'
    }, $true) | Sort-Object { $_.Extent.StartLineNumber })

    if ($newStepCalls.Count -lt 1) {
        return @()
    }

    # For each New-Step, extract its scriptblock body; also track -Retry steps
    $stepBodies      = @()
    $retryStepBodies = @()
    foreach ($call in $newStepCalls) {
        $sb = $call.CommandElements |
            Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } |
            Select-Object -First 1
        if ($sb) {
            $stepBodies += $sb
            $hasRetry = $call.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                $_.ParameterName -eq 'Retry'
            }
            if ($hasRetry) { $retryStepBodies += $sb }
        }
    }

    if ($stepBodies.Count -lt 1) {
        return @()
    }

    # For each step body, collect written vars and read vars
    $stepWrites = @()
    $stepReads  = @()

    foreach ($body in $stepBodies) {
        $writes = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $reads  = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        # Assignments: left-hand side of AssignmentStatementAst
        $assignments = $body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst]
        }, $true)

        foreach ($assign in $assignments) {
            $lhs = $assign.Left
            # Simple: $var = ...
            if ($lhs -is [System.Management.Automation.Language.VariableExpressionAst]) {
                [void]$writes.Add($lhs.VariablePath.UserPath)
            }
        }

        # All variable references (reads)
        $varRefs = $body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)

        foreach ($ref in $varRefs) {
            $name = $ref.VariablePath.UserPath
            # Exclude $Stepper and $Stepper.* (member access is a separate AST node,
            # but the base var would appear as 'Stepper')
            if ($name -eq 'Stepper') { continue }
            [void]$reads.Add($name)
        }

        $stepWrites += ,$writes
        $stepReads  += ,$reads
    }

    # A variable is a cross-step candidate if:
    # - Written in step N
    # - Read in step M where M > N
    $candidates = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    for ($n = 0; $n -lt $stepBodies.Count - 1; $n++) {
        foreach ($varName in $stepWrites[$n]) {
            if ($automaticVars.Contains($varName)) { continue }
            if ($varName -eq 'Stepper') { continue }

            for ($m = $n + 1; $m -lt $stepBodies.Count; $m++) {
                if ($stepReads[$m].Contains($varName)) {
                    [void]$candidates.Add($varName)
                    break
                }
            }
        }
    }

    # Build a set of offset ranges covered by step bodies so we can identify
    # assignments that live in unmanaged (script-level) code
    $stepBodyRanges = $stepBodies | ForEach-Object {
        [PSCustomObject]@{ Start = $_.Extent.StartOffset; End = $_.Extent.EndOffset }
    }

    # Collect variables assigned at script scope (outside any New-Step body)
    $unmanagedWrites = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $allAssignments = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))

    foreach ($assign in $allAssignments) {
        $offset = $assign.Extent.StartOffset
        $insideStep = $false
        foreach ($range in $stepBodyRanges) {
            if ($offset -ge $range.Start -and $offset -lt $range.End) {
                $insideStep = $true
                break
            }
        }
        if (-not $insideStep) {
            $varName = $assign.Left.VariablePath.UserPath
            if (-not $automaticVars.Contains($varName) -and $varName -ne 'Stepper') {
                [void]$unmanagedWrites.Add($varName)
            }
        }
    }

    # Any variable written in unmanaged code and read inside any step is a candidate
    foreach ($varName in $unmanagedWrites) {
        foreach ($reads in $stepReads) {
            if ($reads.Contains($varName)) {
                [void]$candidates.Add($varName)
                break
            }
        }
    }

    # Variables written AND read within the same -Retry step must use $Stepper.* to
    # survive across retry attempts (local vars reset on every execution of the block)
    foreach ($body in $retryStepBodies) {
        $retryWrites = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        $assignments = $body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)
        foreach ($assign in $assignments) {
            $varName = $assign.Left.VariablePath.UserPath
            if (-not $automaticVars.Contains($varName) -and $varName -ne 'Stepper') {
                [void]$retryWrites.Add($varName)
            }
        }

        $varRefs = $body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)
        foreach ($ref in $varRefs) {
            $varName = $ref.VariablePath.UserPath
            # Skip if this is the direct LHS of an assignment (that's a write, not a read)
            $isAssignLhs = $ref.Parent -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                           [object]::ReferenceEquals($ref.Parent.Left, $ref)
            if (-not $isAssignLhs -and $retryWrites.Contains($varName)) {
                [void]$candidates.Add($varName)
            }
        }
    }

    return @($candidates)
}
