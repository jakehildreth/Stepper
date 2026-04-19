function Find-UnmanagedCodeBlocks {
    <#
    .SYNOPSIS
        Identifies unmanaged code blocks between New-Step blocks.

    .DESCRIPTION
        Uses the PowerShell AST and token stream to correctly detect:
          - Multi-line block comment spans (block comments) even when the opener appears after code
          - #region Stepper ignore / #endregion Stepper ignore regions
          - Executable lines via AST statement extents rather than a regex whitelist

        Parameter signature is unchanged from the regex implementation — $ScriptLines is
        joined internally for parsing, and line indices in the return value remain 0-based.

    .PARAMETER ScriptLines
        Array of script lines to analyze.

    .PARAMETER NewStepBlocks
        Array of New-Step block definitions (Start/End), 0-based.

    .PARAMETER StopStepperLine
        0-based line index of Stop-Stepper, or -1 if absent.

    .OUTPUTS
        Array of hashtables with Lines (0-based indices) and IsBeforeStop properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScriptLines,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$NewStepBlocks,

        [Parameter(Mandatory)]
        [int]$StopStepperLine
    )

    $unmanagedBlocks = @()

    # Parse via AST — join lines so token extents match 0-based array indices (+1 for 1-based)
    $scriptContent = $ScriptLines -join [System.Environment]::NewLine
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $scriptContent,
        [ref]$tokens,
        [ref]$parseErrors
    )

    # Build a set of 0-based line numbers covered by executable statements.
    # StatementAst covers all executable constructs. UsingStatementAst is excluded
    # (using namespace/module/assembly directives are not executable code).
    # ParamBlock and CmdletBinding attributes are not StatementAst nodes, so they
    # are excluded by construction.
    $executableLines = [System.Collections.Generic.HashSet[int]]::new()
    $statementNodes = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.StatementAst] -and
        $args[0] -isnot [System.Management.Automation.Language.UsingStatementAst]
    }, $true)
    foreach ($node in $statementNodes) {
        for ($ln = $node.Extent.StartLineNumber; $ln -le $node.Extent.EndLineNumber; $ln++) {
            [void]$executableLines.Add($ln - 1)  # Convert 1-based to 0-based
        }
    }

    # Build sets of 0-based line numbers that are inside ignored or comment regions.
    $ignoredLineSet   = [System.Collections.Generic.HashSet[int]]::new()
    $commentLineSet   = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($token in $tokens) {
        $tokenText  = $token.Text
        $startLine  = $token.Extent.StartLineNumber - 1
        $endLine    = $token.Extent.EndLineNumber - 1

        if ($token.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment) {
            continue
        }

        # Block comment: <# ... #>
        if ($tokenText.StartsWith('<#')) {
            for ($ln = $startLine; $ln -le $endLine; $ln++) {
                [void]$commentLineSet.Add($ln)
            }
            continue
        }

        # #region Stepper ignore / #endregion Stepper ignore markers
        # Collect region boundaries, then fill lines in a second pass below.
    }

    # Second pass: collect #region Stepper ignore boundaries from comment tokens
    $ignoreRegionStack = [System.Collections.Generic.Stack[int]]::new()
    foreach ($token in ($tokens | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment })) {
        $trimmedText = $token.Text.Trim()
        $tokenLine   = $token.Extent.StartLineNumber - 1

        if ($trimmedText -match '^#region\s+Stepper\s+ignore') {
            $ignoreRegionStack.Push($tokenLine)
        } elseif ($trimmedText -match '^#endregion\s+Stepper\s+ignore' -and $ignoreRegionStack.Count -gt 0) {
            $regionStart = $ignoreRegionStack.Pop()
            for ($ln = $regionStart; $ln -le $tokenLine; $ln++) {
                [void]$ignoredLineSet.Add($ln)
            }
        }
    }

    # Helper: check if a 0-based line index should be skipped
    $isSkippedLine = {
        param([int]$lineIndex)
        if ($ignoredLineSet.Contains($lineIndex)) { return $true }
        if ($commentLineSet.Contains($lineIndex))  { return $true }
        if (-not $executableLines.Contains($lineIndex)) { return $true }
        return $false
    }

    if ($NewStepBlocks.Count -gt 0) {
        # Check code BEFORE the first New-Step block
        $firstBlock = $NewStepBlocks[0]
        $blockLines = @()
        for ($j = 0; $j -lt $firstBlock.Start; $j++) {
            if (& $isSkippedLine $j) { continue }
            $blockLines += $j
        }

        if ($blockLines.Count -gt 0) {
            $unmanagedBlocks += @{
                Lines        = $blockLines
                IsBeforeStop = $false
            }
        }

        # Check between consecutive New-Step blocks
        for ($i = 0; $i -lt $NewStepBlocks.Count - 1; $i++) {
            $gapStart = $NewStepBlocks[$i].End + 1
            $gapEnd   = $NewStepBlocks[$i + 1].Start - 1

            $blockLines = @()
            for ($j = $gapStart; $j -le $gapEnd; $j++) {
                if (& $isSkippedLine $j) { continue }
                $blockLines += $j
            }

            if ($blockLines.Count -gt 0) {
                $unmanagedBlocks += @{
                    Lines        = $blockLines
                    IsBeforeStop = $false
                }
            }
        }

        # Check between last New-Step and Stop-Stepper (or end of file)
        $lastBlock = $NewStepBlocks[$NewStepBlocks.Count - 1]
        $gapStart  = $lastBlock.End + 1
        $gapEnd    = if ($StopStepperLine -ge 0) { $StopStepperLine - 1 } else { $ScriptLines.Count - 1 }

        $blockLines = @()
        for ($j = $gapStart; $j -le $gapEnd; $j++) {
            if (& $isSkippedLine $j) { continue }
            $blockLines += $j
        }

        if ($blockLines.Count -gt 0) {
            $unmanagedBlocks += @{
                Lines        = $blockLines
                IsBeforeStop = ($StopStepperLine -ge 0)
            }
        }
    }

    return $unmanagedBlocks
}
