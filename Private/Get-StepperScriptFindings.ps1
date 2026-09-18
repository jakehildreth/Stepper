function Get-StepperScriptFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$ParsedScript,

        [Parameter(Mandatory)]
        [string]$ScriptContent
    )

    $issues = [System.Collections.Generic.List[PSCustomObject]]::new()
    $ast = $ParsedScript.Ast
    $tokens = @($ParsedScript.Tokens)

    if ($ParsedScript.Errors.Count -gt 0) {
        foreach ($parseError in $ParsedScript.Errors) {
            $issues.Add((New-StepperIssue -Code 'ParseError' -Message $parseError.Message -Extent $parseError.Extent))
        }
        return $issues.ToArray()
    }

    $allCommands = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true))

    $getCommandBaseName = {
        param([System.Management.Automation.Language.CommandAst]$Command)
        $name = $Command.GetCommandName()
        if (-not $name) { return $null }
        return ($name -split '\\')[-1]
    }

    $lifecycleCommands = @($allCommands | Where-Object {
        (& $getCommandBaseName $_) -in 'Start-Stepper', 'Initialize-Stepper', 'New-Step', 'Stop-Stepper'
    })
    if ($lifecycleCommands.Count -eq 0) {
        $issues.Add((New-StepperIssue -Code 'NotStepperScript'))
        return $issues.ToArray()
    }

    $rootStatements = @($ast.EndBlock.Statements)
    $isTopLevelCommand = {
        param([System.Management.Automation.Language.CommandAst]$Command)
        if ($Command.Parent -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
        $pipeline = $Command.Parent
        return $rootStatements -contains $pipeline -and
            $pipeline.PipelineElements.Count -eq 1 -and
            $pipeline.PipelineElements[0] -eq $Command
    }

    $locationFromRange = {
        param($FirstExtent, $LastExtent)
        $start = $FirstExtent.StartOffset
        $end = $LastExtent.EndOffset
        [PSCustomObject]@{
            StartLine   = $FirstExtent.StartLineNumber
            StartColumn = $FirstExtent.StartColumnNumber
            EndLine     = $LastExtent.EndLineNumber
            EndColumn   = $LastExtent.EndColumnNumber
            Text        = $ScriptContent.Substring($start, $end - $start)
        }
    }

    # Parse paired, non-nested Stepper-ignore regions from comment tokens.
    $regions = [System.Collections.Generic.List[PSCustomObject]]::new()
    $regionStack = [System.Collections.Generic.Stack[object]]::new()
    $regionMalformed = $false
    foreach ($token in ($tokens | Where-Object Kind -EQ ([System.Management.Automation.Language.TokenKind]::Comment))) {
        $text = $token.Text.Trim()
        if ($text -match '(?i)^#region\s+Stepper\s+ignore\s*$') {
            if ($regionStack.Count -gt 0) {
                $issues.Add((New-StepperIssue -Code 'MalformedIgnoreRegion' -Message 'Stepper-ignore regions cannot be nested.' -Extent $token.Extent))
                $regionMalformed = $true
            }
            $regionStack.Push($token)
        }
        elseif ($text -match '(?i)^#endregion(?:\s+Stepper\s+ignore)?\s*$' -and $regionStack.Count -gt 0) {
            if ($text -notmatch '(?i)^#endregion\s+Stepper\s+ignore\s*$') {
                $issues.Add((New-StepperIssue -Code 'MalformedIgnoreRegion' -Message 'A Stepper-ignore region must end with #endregion Stepper ignore.' -Extent $token.Extent))
                $regionMalformed = $true
            }
            $startToken = $regionStack.Pop()
            $regions.Add([PSCustomObject]@{
                StartLine = $startToken.Extent.StartLineNumber
                EndLine   = $token.Extent.EndLineNumber
                Start     = $startToken
                End       = $token
            })
        }
        elseif ($text -match '(?i)^#endregion\s+Stepper\s+ignore\s*$') {
            $issues.Add((New-StepperIssue -Code 'MalformedIgnoreRegion' -Message 'A Stepper-ignore end marker has no matching start marker.' -Extent $token.Extent))
            $regionMalformed = $true
        }
    }
    while ($regionStack.Count -gt 0) {
        $startToken = $regionStack.Pop()
        $issues.Add((New-StepperIssue -Code 'MalformedIgnoreRegion' -Message 'A Stepper-ignore start marker has no matching end marker.' -Extent $startToken.Extent))
        $regionMalformed = $true
    }

    $isInsideRegion = {
        param([int]$Line)
        foreach ($region in $regions) {
            if ($Line -ge $region.StartLine -and $Line -le $region.EndLine) { return $true }
        }
        return $false
    }

    if (-not $ast.ParamBlock) {
        $issues.Add((New-StepperIssue -Code 'MissingParamBlock'))
    }
    elseif (-not ($ast.ParamBlock.Attributes | Where-Object TypeName | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })) {
        $issues.Add((New-StepperIssue -Code 'MissingCmdletBinding' -Extent $ast.ParamBlock.Extent))
    }

    $isStepperAvailabilityCondition = {
        param($node)

        if ($node -is [System.Management.Automation.Language.PipelineAst]) {
            if ($node.PipelineElements.Count -ne 1) { return $false }
            return & $isStepperAvailabilityCondition $node.PipelineElements[0]
        }
        if ($node -is [System.Management.Automation.Language.CommandExpressionAst]) {
            return & $isStepperAvailabilityCondition $node.Expression
        }
        if ($node -is [System.Management.Automation.Language.ParenExpressionAst]) {
            return & $isStepperAvailabilityCondition $node.Pipeline
        }
        if ($node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            if ($node.Operator -notin @(
                [System.Management.Automation.Language.TokenKind]::And,
                [System.Management.Automation.Language.TokenKind]::AndAnd
            )) { return $false }
            return (& $isStepperAvailabilityCondition $node.Left) -and
                (& $isStepperAvailabilityCondition $node.Right)
        }
        if ($node -isnot [System.Management.Automation.Language.UnaryExpressionAst] -or
            $node.TokenKind -ne [System.Management.Automation.Language.TokenKind]::Not) {
            return $false
        }

        $operand = $node.Child
        while ($operand -is [System.Management.Automation.Language.ParenExpressionAst] -or
            $operand -is [System.Management.Automation.Language.PipelineAst]) {
            if ($operand -is [System.Management.Automation.Language.ParenExpressionAst]) {
                $operand = $operand.Pipeline
            } else {
                if ($operand.PipelineElements.Count -ne 1) { return $false }
                $operand = $operand.PipelineElements[0]
            }
        }
        if ($operand -isnot [System.Management.Automation.Language.CommandAst] -or
            (& $getCommandBaseName $operand) -ne 'Get-Module') {
            return $false
        }
        $values = @($operand.CommandElements | ForEach-Object {
            if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value }
        })
        return $values -contains 'Stepper'
    }

    # Identify Install-Module Stepper calls and validate the exact if-clause that owns each call.
    $installCalls = @($allCommands | Where-Object {
        if ((& $getCommandBaseName $_) -ne 'Install-Module') { return $false }
        $values = @($_.CommandElements | ForEach-Object {
            if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value }
        })
        return $values -contains 'Stepper'
    })

    $validGuards = [System.Collections.Generic.List[object]]::new()
    foreach ($installCall in $installCalls) {
        $owner = $installCall.Parent
        while ($owner -and $owner -isnot [System.Management.Automation.Language.IfStatementAst]) { $owner = $owner.Parent }
        if (-not $owner) { continue }

        $installClause = $null
        foreach ($clause in $owner.Clauses) {
            if ($installCall.Extent.StartOffset -ge $clause.Item2.Extent.StartOffset -and
                $installCall.Extent.EndOffset -le $clause.Item2.Extent.EndOffset) {
                $installClause = $clause
                break
            }
        }
        if (-not $installClause) { continue }

        if (& $isStepperAvailabilityCondition $installClause.Item1) {
            $validGuards.Add($owner)
        }
    }
    $validGuards = @($validGuards | Sort-Object { $_.Extent.StartOffset } -Unique)

    if ($installCalls.Count -eq 0) {
        $issues.Add((New-StepperIssue -Code 'MissingInstallGuard'))
    }
    elseif ($validGuards.Count -eq 0) {
        foreach ($installCall in $installCalls) {
            $issues.Add((New-StepperIssue -Code 'InvalidInstallGuard' -Extent $installCall.Extent))
        }
    }

    $guard = $validGuards | Select-Object -First 1
    $bootstrapRegion = $null
    if ($guard -and -not $regionMalformed) {
        $bootstrapRegion = $regions | Where-Object {
            $guard.Extent.StartLineNumber -ge $_.StartLine -and $guard.Extent.EndLineNumber -le $_.EndLine
        } | Select-Object -First 1
        if (-not $bootstrapRegion) {
            $issues.Add((New-StepperIssue -Code 'MissingBootstrapRegion' -Extent $guard.Extent))
        }

        $precedingExecutable = @($rootStatements | Where-Object {
            $_.Extent.EndOffset -le $guard.Extent.StartOffset -and
            $_ -isnot [System.Management.Automation.Language.UsingStatementAst]
        })
        if ($rootStatements -notcontains $guard -or
            ($ast.ParamBlock -and $guard.Extent.StartOffset -lt $ast.ParamBlock.Extent.EndOffset) -or
            $precedingExecutable.Count -gt 0) {
            $issues.Add((New-StepperIssue -Code 'MisplacedInstallGuard' -Extent $guard.Extent))
        }
    }

    $startCalls = @($lifecycleCommands | Where-Object { (& $getCommandBaseName $_) -in 'Start-Stepper', 'Initialize-Stepper' } | Sort-Object { $_.Extent.StartOffset })
    $topLevelStarts = @($startCalls | Where-Object { & $isTopLevelCommand $_ })
    foreach ($nestedStart in ($startCalls | Where-Object { -not (& $isTopLevelCommand $_) })) {
        $issues.Add((New-StepperIssue -Code 'NestedStartStepper' -Extent $nestedStart.Extent))
    }
    if ($startCalls.Count -gt 1) {
        foreach ($duplicate in ($startCalls | Select-Object -Skip 1)) {
            $issues.Add((New-StepperIssue -Code 'DuplicateStartStepper' -Extent $duplicate.Extent))
        }
    }
    if ($topLevelStarts.Count -eq 0) {
        $issues.Add((New-StepperIssue -Code 'MissingStartStepper'))
    }

    $start = $topLevelStarts | Select-Object -First 1
    if ($start -and $guard) {
        if ($start.Extent.StartOffset -lt $guard.Extent.EndOffset) {
            $issues.Add((New-StepperIssue -Code 'StartBeforeInstallGuard' -Extent $start.Extent))
        }
        if ($bootstrapRegion -and
            ($start.Extent.StartLineNumber -lt $bootstrapRegion.StartLine -or $start.Extent.EndLineNumber -gt $bootstrapRegion.EndLine)) {
            $issues.Add((New-StepperIssue -Code 'StartOutsideBootstrapRegion' -Extent $start.Extent))
        }

        $between = @($rootStatements | Where-Object {
            $_.Extent.StartOffset -ge $guard.Extent.EndOffset -and $_.Extent.EndOffset -le $start.Extent.StartOffset -and $_ -ne $guard
        })
        foreach ($statement in $between) {
            if ($statement -ne $start.Parent) {
                $issues.Add((New-StepperIssue -Code 'StartAfterExecutableCode' -Extent $start.Extent))
                break
            }
        }
    }

    $newStepCalls = @($lifecycleCommands | Where-Object { (& $getCommandBaseName $_) -eq 'New-Step' } | Sort-Object { $_.Extent.StartOffset })
    if ($newStepCalls.Count -eq 0) { $issues.Add((New-StepperIssue -Code 'NoSteps')) }
    foreach ($newStep in $newStepCalls) {
        $isRoot = & $isTopLevelCommand $newStep
        if (-not $isRoot) { $issues.Add((New-StepperIssue -Code 'NestedNewStep' -Extent $newStep.Extent)) }
        $scriptBlock = $newStep.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } | Select-Object -First 1
        if (-not $scriptBlock) { $issues.Add((New-StepperIssue -Code 'MissingStepScriptBlock' -Extent $newStep.Extent)) }
        if ($start -and $newStep.Extent.StartOffset -lt $start.Extent.StartOffset) {
            $issues.Add((New-StepperIssue -Code 'NewStepBeforeStart' -Extent $newStep.Extent))
        }
    }

    $stopCalls = @($lifecycleCommands | Where-Object { (& $getCommandBaseName $_) -eq 'Stop-Stepper' } | Sort-Object { $_.Extent.StartOffset })
    $topLevelStops = @($stopCalls | Where-Object { & $isTopLevelCommand $_ })
    foreach ($nestedStop in ($stopCalls | Where-Object { -not (& $isTopLevelCommand $_) })) {
        $issues.Add((New-StepperIssue -Code 'NestedStopStepper' -Extent $nestedStop.Extent))
    }
    if ($stopCalls.Count -gt 1) {
        foreach ($duplicate in ($stopCalls | Select-Object -Skip 1)) {
            $issues.Add((New-StepperIssue -Code 'DuplicateStopStepper' -Extent $duplicate.Extent))
        }
    }
    if ($stopCalls.Count -eq 0) { $issues.Add((New-StepperIssue -Code 'MissingStopStepper')) }

    $stop = $topLevelStops | Select-Object -First 1
    if ($stop) {
        foreach ($newStep in $newStepCalls) {
            if ($newStep.Extent.StartOffset -gt $stop.Extent.StartOffset) {
                $issues.Add((New-StepperIssue -Code 'NewStepAfterStop' -Extent $newStep.Extent))
            }
        }
    }

    # Root statements not owned by lifecycle/bootstrap are user code.
    $lifecycleRootStatements = @($lifecycleCommands | Where-Object { & $isTopLevelCommand $_ } | ForEach-Object Parent)
    $userStatements = [System.Collections.Generic.List[object]]::new()
    for ($rootIndex = 0; $rootIndex -lt $rootStatements.Count; $rootIndex++) {
        $statement = $rootStatements[$rootIndex]
        if ($statement -is [System.Management.Automation.Language.UsingStatementAst]) { continue }
        if ($statement -eq $guard) { continue }
        if ($lifecycleRootStatements -contains $statement) { continue }
        if (& $isInsideRegion $statement.Extent.StartLineNumber) { continue }
        $userStatements.Add([PSCustomObject]@{ Statement = $statement; RootIndex = $rootIndex })
    }

    if ($stop) {
        $afterStop = @($userStatements | Where-Object { $_.Statement.Extent.StartOffset -gt $stop.Extent.EndOffset })
        foreach ($entry in $afterStop) {
            $issues.Add((New-StepperIssue -Code 'ExecutableCodeAfterStop' -Extent $entry.Statement.Extent))
        }
    }

    if (-not $regionMalformed) {
        $unmanagedEntries = @($userStatements | Where-Object {
            -not $stop -or $_.Statement.Extent.StartOffset -lt $stop.Extent.StartOffset
        })
        $currentGroup = [System.Collections.Generic.List[object]]::new()
        $previousIndex = -2
        foreach ($entry in $unmanagedEntries) {
            if ($currentGroup.Count -gt 0 -and $entry.RootIndex -ne ($previousIndex + 1)) {
                $issues.Add((New-StepperIssue -Code 'UnmanagedCode' -Location (& $locationFromRange $currentGroup[0].Statement.Extent $currentGroup[$currentGroup.Count - 1].Statement.Extent)))
                $currentGroup.Clear()
            }
            $currentGroup.Add($entry)
            $previousIndex = $entry.RootIndex
        }
        if ($currentGroup.Count -gt 0) {
            $issues.Add((New-StepperIssue -Code 'UnmanagedCode' -Location (& $locationFromRange $currentGroup[0].Statement.Extent $currentGroup[$currentGroup.Count - 1].Statement.Extent)))
        }
    }

    return $issues.ToArray()
}
