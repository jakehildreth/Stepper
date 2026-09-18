function Invoke-StepperScriptRepair {
    <#
    .SYNOPSIS
        Applies deterministic Stepper script repairs as one transaction.

    .DESCRIPTION
        Builds one dependency-ordered repair plan from a current Test-StepperScript
        result. Eligible additions are composed in memory, then applied with one
        backup and one write. A successful write removes stale Stepper state and
        returns fresh Test-StepperScript findings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [PSCustomObject]$TestResult,

        [Parameter()]
        [switch]$Preview
    )

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    if (-not $TestResult.PSObject.Properties['Path'] -or
        -not $TestResult.PSObject.Properties['IsValid'] -or
        -not $TestResult.PSObject.Properties['Issues']) {
        throw [System.ArgumentException]::new('TestResult must be a current Test-StepperScript result.')
    }

    $testResultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath([string]$TestResult.Path)
    if (-not [string]::Equals($resolvedPath, $testResultPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.ArgumentException]::new("TestResult path '$testResultPath' does not match script path '$resolvedPath'.")
    }

    $newResult = {
        param(
            [PSCustomObject]$Result,
            [bool]$Changed,
            [AllowNull()]
            [string]$BackupPath,
            [string[]]$AppliedRepairs,
            [string[]]$PlannedRepairs
        )

        [PSCustomObject]@{
            Path            = $Result.Path
            IsValid         = $Result.IsValid
            Issues          = @($Result.Issues)
            Changed         = $Changed
            BackupPath      = $BackupPath
            AppliedRepairs  = @($AppliedRepairs)
            PlannedRepairs  = @($PlannedRepairs)
        }
    }

    $parseContent = {
        param([string]$Content)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Content,
            [ref]$tokens,
            [ref]$errors
        )

        [PSCustomObject]@{
            Ast    = $ast
            Tokens = @($tokens)
            Errors = @($errors)
        }
    }

    $insertBlock = {
        param(
            [string]$Content,
            [int]$Offset,
            [string]$Block,
            [string]$NewLine
        )

        $prefixSeparator = ''
        if ($Offset -gt 0 -and $Content[$Offset - 1] -notin "`r", "`n") {
            $prefixSeparator = $NewLine
        }

        $suffixSeparator = ''
        if ($Offset -lt $Content.Length -and $Content[$Offset] -notin "`r", "`n") {
            $suffixSeparator = $NewLine
        }

        $Content.Substring(0, $Offset) +
            $prefixSeparator +
            $Block +
            $suffixSeparator +
            $Content.Substring($Offset)
    }

    $getCanonicalGuard = {
        param([PSCustomObject]$Parsed)

        $getCommandBaseName = {
            param([System.Management.Automation.Language.CommandAst]$Command)
            $name = $Command.GetCommandName()
            if (-not $name) { return $null }
            return ($name -split '\\')[-1]
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

        $ast = $Parsed.Ast
        $rootStatements = @($ast.EndBlock.Statements)
        $installCalls = @($ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.CommandAst] -or
                (& $getCommandBaseName $node) -ne 'Install-Module') {
                return $false
            }

            $values = @($node.CommandElements | ForEach-Object {
                if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $_.Value
                }
            })
            return $values -contains 'Stepper'
        }, $true))

        foreach ($installCall in $installCalls) {
            $guard = $installCall.Parent
            while ($guard -and $guard -isnot [System.Management.Automation.Language.IfStatementAst]) {
                $guard = $guard.Parent
            }
            if (-not $guard -or $rootStatements -notcontains $guard) { continue }
            if ($ast.ParamBlock -and $guard.Extent.StartOffset -lt $ast.ParamBlock.Extent.EndOffset) { continue }

            if (& $isStepperAvailabilityCondition $guard.Clauses[0].Item1) {
                return $guard
            }
        }

        return $null
    }

    $getBootstrapRegion = {
        param(
            [PSCustomObject]$Parsed,
            [System.Management.Automation.Language.IfStatementAst]$Guard
        )

        $regions = [System.Collections.Generic.List[object]]::new()
        $stack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($token in ($Parsed.Tokens | Where-Object Kind -EQ ([System.Management.Automation.Language.TokenKind]::Comment))) {
            $text = $token.Text.Trim()
            if ($text -match '(?i)^#region\s+Stepper\s+ignore\s*$') {
                if ($stack.Count -gt 0) { return $null }
                $stack.Push($token)
            }
            elseif ($text -match '(?i)^#endregion\s+Stepper\s+ignore\s*$') {
                if ($stack.Count -eq 0) { return $null }
                $start = $stack.Pop()
                $regions.Add([PSCustomObject]@{
                    StartOffset = $start.Extent.StartOffset
                    EndOffset   = $token.Extent.EndOffset
                })
            }
        }
        if ($stack.Count -gt 0) { return $null }

        return $regions | Where-Object {
            $Guard.Extent.StartOffset -ge $_.StartOffset -and
            $Guard.Extent.EndOffset -le $_.EndOffset
        } | Select-Object -First 1
    }

    $originalContent = Get-Content -LiteralPath $resolvedPath -Raw -ErrorAction Stop
    $newLine = if ($originalContent.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = $originalContent
    $parsed = & $parseContent $content
    $plannedRepairs = [System.Collections.Generic.List[string]]::new()
    $issueCodes = @($TestResult.Issues | ForEach-Object Code)

    if ($parsed.Errors.Count -eq 0 -and $issueCodes -contains 'MissingParamBlock') {
        $usingStatements = @($parsed.Ast.UsingStatements)
        if ($usingStatements.Count -gt 0) {
            $insertOffset = $usingStatements[-1].Extent.EndOffset
        }
        else {
            $firstStatement = @($parsed.Ast.EndBlock.Statements) | Select-Object -First 1
            $insertOffset = if ($firstStatement) { $firstStatement.Extent.StartOffset } else { $content.Length }
        }

        $content = & $insertBlock $content $insertOffset ("[CmdletBinding()]${newLine}param()") $newLine
        $plannedRepairs.Add('MissingParamBlock')
        $parsed = & $parseContent $content
    }
    elseif ($parsed.Errors.Count -eq 0 -and
        $issueCodes -contains 'MissingCmdletBinding' -and
        $parsed.Ast.ParamBlock) {
        $content = & $insertBlock $content $parsed.Ast.ParamBlock.Extent.StartOffset '[CmdletBinding()]' $newLine
        $plannedRepairs.Add('MissingCmdletBinding')
        $parsed = & $parseContent $content
    }

    if ($parsed.Errors.Count -eq 0 -and
        $issueCodes -contains 'MissingInstallGuard' -and
        $parsed.Ast.ParamBlock) {
        $guardBlock = @(
            '#region Stepper ignore'
            'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
            '#endregion Stepper ignore'
        ) -join $newLine
        $content = & $insertBlock $content $parsed.Ast.ParamBlock.Extent.EndOffset $guardBlock $newLine
        $plannedRepairs.Add('MissingInstallGuard')
        $parsed = & $parseContent $content
    }
    elseif ($parsed.Errors.Count -eq 0 -and $issueCodes -contains 'MissingBootstrapRegion') {
        $guard = & $getCanonicalGuard $parsed
        if ($guard) {
            $content = & $insertBlock $content $guard.Extent.EndOffset '#endregion Stepper ignore' $newLine
            $content = & $insertBlock $content $guard.Extent.StartOffset '#region Stepper ignore' $newLine
            $plannedRepairs.Add('MissingBootstrapRegion')
            $parsed = & $parseContent $content
        }
    }

    if ($parsed.Errors.Count -eq 0 -and $issueCodes -contains 'MissingStartStepper') {
        $guard = & $getCanonicalGuard $parsed
        if ($guard) {
            $bootstrapRegion = & $getBootstrapRegion $parsed $guard
            if ($bootstrapRegion) {
                $content = & $insertBlock $content $guard.Extent.EndOffset 'Start-Stepper' $newLine
                $plannedRepairs.Add('MissingStartStepper')
                $parsed = & $parseContent $content
            }
        }
    }

    $planned = @($plannedRepairs)
    if ($planned.Count -eq 0) {
        return & $newResult $TestResult $false $null @() $planned
    }

    if ($Preview) {
        return & $newResult $TestResult $false $null @() $planned
    }

    $action = "Apply deterministic repairs: $($planned -join ', ')"
    if (-not $PSCmdlet.ShouldProcess($resolvedPath, $action)) {
        return & $newResult $TestResult $false $null @() $planned
    }

    $backupPath = $null
    try {
        $backupPath = New-StepperBackup -Path $resolvedPath -ErrorAction Stop
        if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath)) {
            throw "Backup was not created for '$resolvedPath'."
        }
    }
    catch {
        $exception = [System.IO.IOException]::new(
            "Failed to create a backup for '$resolvedPath'. The script was not changed.",
            $_.Exception
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StepperRepairBackupFailed',
            [System.Management.Automation.ErrorCategory]::WriteError,
            $resolvedPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    try {
        Set-Content -LiteralPath $resolvedPath -Value $content -Encoding UTF8 -NoNewline -Force -ErrorAction Stop
    }
    catch {
        $exception = [System.IO.IOException]::new(
            "Failed to write repaired script '$resolvedPath'. Backup: '$backupPath'.",
            $_.Exception
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StepperRepairWriteFailed',
            [System.Management.Automation.ErrorCategory]::WriteError,
            $resolvedPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $statePath = Get-StepperStatePath -ScriptPath $resolvedPath
    Remove-StepperState -StatePath $statePath -ErrorAction Stop

    $postRepairResult = Test-StepperScript -ScriptPath $resolvedPath
    return & $newResult $postRepairResult $true $backupPath $planned $planned
}
