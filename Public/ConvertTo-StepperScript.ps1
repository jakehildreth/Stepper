function ConvertTo-StepperScript {
    <#
    .SYNOPSIS
        Rewrites cross-step plain variables to $Stepper.<Var> notation.

    .DESCRIPTION
        Uses Find-CrossStepVariables to identify variables that are assigned in one
        New-Step block and read in a later one. For each candidate, prompts the user
        to confirm the rewrite (skipped with -Force).

        By default the source file is modified in-place and a .bak backup is created.
        When -OutputPath is provided the rewritten content is written there and the
        source is not modified (no .bak).

        A completed review writes $StepperConversionComplete = $true even when every
        candidate is declined. Quitting writes nothing. In-place rewrites remove
        stale Stepper state and return a result whose RerunRequired property is true.

    .PARAMETER Path
        Path to the script file to convert.

    .PARAMETER Name
        Script filename (with or without .ps1 extension). Used with -Directory.

    .PARAMETER Directory
        Directory containing the script. Defaults to the current working directory.

    .PARAMETER OutputPath
        If provided, write the rewritten content here instead of modifying the source.
        No .bak file is created when this parameter is used.

    .PARAMETER Force
        Explicitly convert all candidates without per-variable confirmation.

    .OUTPUTS
        PSCustomObject describing the outcome. RerunRequired is true after any
        in-place conversion or sentinel rewrite.

    .EXAMPLE
        ConvertTo-StepperScript -Path ./Deploy.ps1

    .EXAMPLE
        ConvertTo-StepperScript -Name Deploy.ps1 -Directory ./scripts -Force

    .EXAMPLE
        ConvertTo-StepperScript -Path ./Deploy.ps1 -OutputPath ./Deploy.converted.ps1 -Force
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByPath', Mandatory)]
        [Alias('ScriptPath')]
        [string]$Path,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$Directory = $PWD,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$Force
    )

    # Resolve script path
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $scriptName = if ($Name -match '\.ps1$') { $Name } else { "$Name.ps1" }
        $resolvedPath = Join-Path $Directory $scriptName
    } else {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        $exception = [System.IO.FileNotFoundException]::new("Script not found: '$resolvedPath'")
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ScriptNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $resolvedPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    # Find candidates
    $candidates = @(Find-CrossStepVariables -ScriptPath $resolvedPath)

    if ($candidates.Count -eq 0) {
        Write-Host "No cross-step variable candidates found in '$resolvedPath'." -ForegroundColor Gray
        return [PSCustomObject]@{
            Status          = 'NoCandidates'
            Changed         = $false
            RerunRequired   = $false
            CandidateCount  = 0
            ConvertedCount  = 0
            BackupPath      = $null
            TargetPath      = $resolvedPath
        }
    }

    # Interactive selection (skipped only by the explicit -Force opt-in)
    $selected = [System.Collections.Generic.List[string]]::new()
    $reviewCompleted = $false
    if ($Force) {
        foreach ($c in $candidates) { [void]$selected.Add($c) }
        $reviewCompleted = $true
    } else {
        $scriptName = Split-Path $resolvedPath -Leaf
        Write-Host ""
        Write-Host "[i] Cross-step variables detected in $scriptName." -ForegroundColor Cyan
        Write-Host "    These variables cross step boundaries, i.e. they are assigned in a"
        Write-Host "    preceding step or unmanaged code then later read inside a step."
        Write-Host "    Converting them to `$Stepper.<Var> notation ensures they persist across steps."
        Write-Host ""

        $convertAll = $false
        foreach ($var in $candidates) {
            if ($convertAll) {
                [void]$selected.Add($var)
                continue
            }

            $capitalized = [char]::ToUpper($var[0]) + $var.Substring(1)
            Write-Host "Convert " -NoNewline
            Write-Host "`$$var" -NoNewline -ForegroundColor Yellow
            Write-Host " to " -NoNewline
            Write-Host "`$Stepper.$capitalized" -NoNewline -ForegroundColor Green
            Write-Host "?"
            Write-Host ""
            Write-Host "  [Y] Yes (Default)" -ForegroundColor Cyan
            Write-Host "  [n] No, skip this variable" -ForegroundColor White
            Write-Host "  [a] All, convert all remaining candidates" -ForegroundColor White
            Write-Host "  [q] Quit, stop conversion" -ForegroundColor White
            Write-Host ""
            Write-Host "Choice? [" -NoNewline
            Write-Host "Y" -NoNewline -ForegroundColor Cyan
            Write-Host "/n/a/q]: " -NoNewline
            $answer = Read-StepperChoice -NonInteractiveDefault '__StepperNonInteractive__'
            if ($answer -eq '__StepperNonInteractive__') {
                $exception = [System.InvalidOperationException]::new(
                    "Cross-step variable conversion for '$resolvedPath' requires an interactive review. Run ConvertTo-StepperScript in an interactive PowerShell session and choose Yes, No, All, or Quit for each candidate."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'CrossStepConversionReviewRequired',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $resolvedPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            Write-Host ""
            switch -Regex ($answer.Trim().ToLower()) {
                '^n(o)?$'   { <# skip #> }
                '^a(ll)?$'  {
                    [void]$selected.Add($var)
                    $convertAll = $true
                }
                '^q(uit)?$' {
                    Write-Host 'Stepper stopped; no changes were made.' -ForegroundColor Gray
                    return [PSCustomObject]@{
                        Status          = 'Quit'
                        Changed         = $false
                        RerunRequired   = $false
                        CandidateCount  = $candidates.Count
                        ConvertedCount  = 0
                        BackupPath      = $null
                        TargetPath      = $resolvedPath
                    }
                }
                default     { [void]$selected.Add($var) }  # y, empty, or anything else = yes
            }
        }
        $reviewCompleted = $true
    }

    # Read script content (keep original for .bak)
    $originalContent = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8
    $content = $originalContent

    # Parse AST to find all New-Step scriptblock bodies
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $content, [ref]$tokens, [ref]$errors
    )

    # Collect all New-Step CommandAst nodes
    $newStepCalls = @($ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        $name = $node.GetCommandName()
        if ($name) { $name = ($name -split '\\')[-1] }
        return $name -eq 'New-Step'
    }, $true))

    # Collect scriptblock bodies
    $stepBodies = @()
    foreach ($call in $newStepCalls) {
        $sb = $call.CommandElements |
            Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } |
            Select-Object -First 1
        if ($sb) { $stepBodies += $sb }
    }

    # Build a set of selected names for O(1) lookup
    $selectedSet = [System.Collections.Generic.HashSet[string]]::new(
        $selected,
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # Collect all VariableExpressionAst occurrences inside step bodies for selected vars
    $occurrences = [System.Collections.Generic.List[System.Management.Automation.Language.VariableExpressionAst]]::new()
    foreach ($body in $stepBodies) {
        $vars = $body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)
        foreach ($v in $vars) {
            if ($selectedSet.Contains($v.VariablePath.UserPath)) {
                [void]$occurrences.Add($v)
            }
        }
    }

    # Also collect occurrences in unmanaged (script-level) code, outside all step bodies.
    # Variables assigned there and read in steps are candidates too, and their script-level
    # uses must be rewritten so they stay in sync with $Stepper.<Var>.
    $stepBodyRanges = $stepBodies | ForEach-Object {
        [PSCustomObject]@{ Start = $_.Extent.StartOffset; End = $_.Extent.EndOffset }
    }
    $allVarRefs = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))
    foreach ($v in $allVarRefs) {
        if (-not $selectedSet.Contains($v.VariablePath.UserPath)) { continue }
        $offset = $v.Extent.StartOffset
        $insideStep = $false
        foreach ($range in $stepBodyRanges) {
            if ($offset -ge $range.Start -and $offset -lt $range.End) {
                $insideStep = $true
                break
            }
        }
        if (-not $insideStep) {
            [void]$occurrences.Add($v)
        }
    }

    # Sort descending by StartOffset so back-to-front rewriting preserves offsets
    $sorted = @($occurrences | Sort-Object { $_.Extent.StartOffset } -Descending)

    $target = if ($OutputPath) { $OutputPath } else { $resolvedPath }

    if (-not $PSCmdlet.ShouldProcess($target, 'Convert cross-step variables to $Stepper.<Var>')) {
        return [PSCustomObject]@{
            Status          = 'Skipped'
            Changed         = $false
            RerunRequired   = $false
            CandidateCount  = $candidates.Count
            ConvertedCount  = 0
            BackupPath      = $null
            TargetPath      = $target
        }
    }

    foreach ($v in $sorted) {
        $varName    = $v.VariablePath.UserPath
        $capitalized = [char]::ToUpper($varName[0]) + $varName.Substring(1)
        $replacement = "`$Stepper.$capitalized"

        $start = $v.Extent.StartOffset
        $end   = $v.Extent.EndOffset   # exclusive

        # Rebuild: prefix + replacement + suffix
        $prefix  = $content.Substring(0, $start)
        $suffix  = $content.Substring($end)
        $content = $prefix + $replacement + $suffix
    }

    # A completed review always writes the sentinel, even when every candidate was declined.
    $nl = [System.Environment]::NewLine
    if ($selected.Count -gt 0 -and $content -notmatch '\b(Start-Stepper|Initialize-Stepper)\b') {
        $scriptLines = $content -split '\r?\n'
        $insertIndex = Get-StepperInitInsertionIndex -ScriptPath $resolvedPath
        $newLines = @()
        for ($i = 0; $i -lt $insertIndex; $i++) { $newLines += $scriptLines[$i] }
        $newLines += 'Start-Stepper'
        for ($i = $insertIndex; $i -lt $scriptLines.Count; $i++) { $newLines += $scriptLines[$i] }
        $content = $newLines -join $nl
    }

    if ($reviewCompleted) {
        $sentinelTokens = $null
        $sentinelErrors = $null
        $sentinelAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$sentinelTokens, [ref]$sentinelErrors
        )
        $sentinelAssignments = @($sentinelAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq 'StepperConversionComplete'
        }, $false))

        if ($sentinelAssignments.Count -gt 0) {
            foreach ($assignment in @($sentinelAssignments | Sort-Object { $_.Right.Extent.StartOffset } -Descending)) {
                $content = $content.Substring(0, $assignment.Right.Extent.StartOffset) +
                    '$true' +
                    $content.Substring($assignment.Right.Extent.EndOffset)
            }
        } else {
            $endRegionToken = @($sentinelTokens | Where-Object {
                $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment -and
                $_.Text.Trim() -match '(?i)^#endregion\s+Stepper\s+ignore\s*$'
            } | Select-Object -First 1)
            $endRegionIndex = if ($endRegionToken) { $endRegionToken[0].Extent.StartOffset } else { -1 }

            if ($endRegionIndex -ge 0) {
                $content = $content.Substring(0, $endRegionIndex) +
                    '$StepperConversionComplete = $true' + $nl +
                    $content.Substring($endRegionIndex)
            } else {
                $insertOffset = if ($sentinelAst.ParamBlock) {
                    $sentinelAst.ParamBlock.Extent.EndOffset
                } else {
                    $firstStatement = @($sentinelAst.EndBlock.Statements) | Select-Object -First 1
                    if ($firstStatement) { $firstStatement.Extent.StartOffset } else { $content.Length }
                }

                $installGuard = $nl +
                    '#region Stepper ignore' + $nl +
                    "if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }" + $nl +
                    '$StepperConversionComplete = $true' + $nl +
                    '#endregion Stepper ignore' + $nl
                $content = $content.Substring(0, $insertOffset) +
                    $installGuard +
                    $content.Substring($insertOffset)
            }
        }
    }

    $backupPath = $null
    if ($OutputPath) {
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)
    } else {
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
                'ConversionBackupFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $resolvedPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        try {
            [System.IO.File]::WriteAllText($resolvedPath, $content, [System.Text.Encoding]::UTF8)
        }
        catch {
            $exception = [System.IO.IOException]::new(
                "Failed to write converted script '$resolvedPath'. Backup: '$backupPath'.",
                $_.Exception
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'ConversionWriteFailed',
                [System.Management.Automation.ErrorCategory]::WriteError,
                $resolvedPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $statePath = Get-StepperStatePath -ScriptPath $resolvedPath
        Remove-StepperState -StatePath $statePath -ErrorAction Stop
    }

    if ($selected.Count -eq 0) {
        Write-Host "Cross-step variable review completed for '$target'; no candidates were converted." -ForegroundColor Green
    } else {
        Write-Host "Converted $($occurrences.Count) occurrence(s) in '$target'." -ForegroundColor Green
    }

    if (-not $OutputPath) {
        Write-Host "Backup: $backupPath" -ForegroundColor Gray
        Write-Host "Please re-run $(Split-Path $resolvedPath -Leaf)." -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Status          = if ($OutputPath) { 'WrittenToOutput' } else { 'RerunRequired' }
        Changed         = $true
        RerunRequired   = -not [bool]$OutputPath
        CandidateCount  = $candidates.Count
        ConvertedCount  = $selected.Count
        BackupPath      = $backupPath
        TargetPath      = $target
    }
}
