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
        Write-Information "No cross-step variable candidates found in '$resolvedPath'." -InformationAction Continue
        return
    }

    # Interactive selection (skipped with -Force)
    $selected = [System.Collections.Generic.List[string]]::new()
    if ($Force) {
        foreach ($c in $candidates) { [void]$selected.Add($c) }
    } else {
        foreach ($var in $candidates) {
            $answer = Read-Host "Convert `$$var to `$Stepper.$([char]::ToUpper($var[0]) + $var.Substring(1))? [y/N/all/quit]"
            switch -Regex ($answer.Trim().ToLower()) {
                '^y(es)?$' { [void]$selected.Add($var) }
                '^a(ll)?$' {
                    foreach ($c in $candidates) { [void]$selected.Add($c) }
                    break
                }
                '^q(uit)?$' { return }
                default { <# skip #> }
            }
        }
    }

    if ($selected.Count -eq 0) {
        Write-Information 'No variables selected for conversion.' -InformationAction Continue
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

    if ($occurrences.Count -eq 0) {
        Write-Information 'No occurrences to rewrite.' -InformationAction Continue
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

    if ($OutputPath) {
        # Write to output path only; source untouched, no .bak
        [System.IO.File]::WriteAllText($OutputPath, $content, [System.Text.Encoding]::UTF8)
    } else {
        # In-place: write .bak then overwrite source
        [System.IO.File]::WriteAllText("$resolvedPath.bak", $originalContent, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($resolvedPath, $content, [System.Text.Encoding]::UTF8)
    }

    Write-Information "Converted $($occurrences.Count) occurrence(s) in '$target'." -InformationAction Continue
}
