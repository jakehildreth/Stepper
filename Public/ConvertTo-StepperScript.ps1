function ConvertTo-StepperScript {
    <#
    .SYNOPSIS
        Rewrites cross-step plain variables to $Stepper.<Var> notation.

    .DESCRIPTION
        Uses Find-CrossStepVariables to identify variables that are assigned in one
        New-Step block and read in a later one. For each candidate, prompts the user
        to confirm the rewrite (skipped with -Force). Rewrites only occurrences
        inside New-Step scriptblock bodies, leaving script-level code untouched.

        By default the source file is modified in-place and a .bak backup is created.
        When -OutputPath is provided the rewritten content is written there and the
        source is not modified (no .bak).

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
        Skip interactive per-variable confirmation and convert all candidates.

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
        $resolvedPath = $Path
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
        return
    }

    # Interactive selection (skipped with -Force)
    $selected = [System.Collections.Generic.List[string]]::new()
    if ($Force) {
        foreach ($c in $candidates) { [void]$selected.Add($c) }
    } else {
        $scriptName = Split-Path $resolvedPath -Leaf
        Write-Host ""
        Write-Host "[i] Cross-step variables detected in $scriptName." -ForegroundColor Cyan
        Write-Host "    These variables cross step boundaries, i.e. they are assigned in a"
        Write-Host "    preceding step or unmanaged code then later read inside a step."
        Write-Host "    Converting them to `$Stepper.<Var> notation ensures they persist across steps."
        Write-Host ""

        foreach ($var in $candidates) {
            $capitalized = [char]::ToUpper($var[0]) + $var.Substring(1)
            Write-Host "Convert " -NoNewline
            Write-Host "`$$var" -NoNewline -ForegroundColor Yellow
            Write-Host " to " -NoNewline
            Write-Host "`$Stepper.$capitalized" -NoNewline -ForegroundColor Green
            Write-Host "?"
            Write-Host ""
            Write-Host "  [Y] Yes (Default)" -ForegroundColor Cyan
            Write-Host "  [n] No — skip this variable" -ForegroundColor White
            Write-Host "  [a] All — convert all remaining candidates" -ForegroundColor White
            Write-Host "  [q] Quit — stop conversion" -ForegroundColor White
            Write-Host ""
            Write-Host "Choice? [" -NoNewline
            Write-Host "Y" -NoNewline -ForegroundColor Cyan
            Write-Host "/n/a/q]: " -NoNewline
            try {
                $answer = Read-Host
            } catch {
                $answer = 'y'
            }
            Write-Host ""
            switch -Regex ($answer.Trim().ToLower()) {
                '^n(o)?$'   { <# skip #> }
                '^a(ll)?$'  {
                    foreach ($c in $candidates) { [void]$selected.Add($c) }
                    break
                }
                '^q(uit)?$' { return }
                default     { [void]$selected.Add($var) }  # y, empty, or anything else = yes
            }
        }
    }

    if ($selected.Count -eq 0) {
        Write-Host 'No variables selected for conversion.' -ForegroundColor Gray
        return
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
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'New-Step'
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

    # Also collect occurrences in unmanaged (script-level) code — outside all step bodies.
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

    if ($occurrences.Count -eq 0) {
        Write-Host 'No occurrences to rewrite.' -ForegroundColor Gray
        return
    }

    # Sort descending by StartOffset so back-to-front rewriting preserves offsets
    $sorted = @($occurrences | Sort-Object { $_.Extent.StartOffset } -Descending)

    $target = if ($OutputPath) { $OutputPath } else { $resolvedPath }

    if (-not $PSCmdlet.ShouldProcess($target, 'Convert cross-step variables to $Stepper.<Var>')) {
        return
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

    # Inject $StepperConversionComplete sentinel inside the #region Stepper ignore block
    $nl = [System.Environment]::NewLine
    $endRegionPattern = '#endregion Stepper ignore'
    $endRegionIndex = $content.IndexOf($endRegionPattern)

    if ($endRegionIndex -ge 0) {
        # Insert the sentinel on the line immediately before #endregion Stepper ignore
        $content = $content.Substring(0, $endRegionIndex) +
            '$StepperConversionComplete = $true' + $nl +
            $content.Substring($endRegionIndex)
    } else {
        # No existing ignore region — create a new one before the first New-Step call
        $sentinelAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$null, [ref]$null
        )
        $firstNewStep = @($sentinelAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'New-Step'
        }, $true) | Sort-Object { $_.Extent.StartLineNumber }) | Select-Object -First 1

        if ($firstNewStep) {
            $insertOffset = $firstNewStep.Extent.StartOffset
            $sentinel = '#region Stepper ignore' + $nl +
                        '$StepperConversionComplete = $true' + $nl +
                        '#endregion Stepper ignore' + $nl
            $content = $content.Substring(0, $insertOffset) +
                $sentinel +
                $content.Substring($insertOffset)
        }
    }

    if ($OutputPath) {
        # Write to output path only; source untouched, no .bak
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)
    } else {
        # In-place: backup then overwrite source
        New-StepperBackup -Path $resolvedPath | Out-Null
        [System.IO.File]::WriteAllText($resolvedPath, $content, [System.Text.Encoding]::UTF8)
    }

    Write-Host "Converted $($occurrences.Count) occurrence(s) in '$target'." -ForegroundColor Green
}
