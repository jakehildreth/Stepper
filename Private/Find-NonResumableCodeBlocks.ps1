function Find-NonResumableCodeBlocks {
    <#
    .SYNOPSIS
        Identifies non-resumable code blocks between New-Step blocks.

    .PARAMETER ScriptLines
        Array of script lines to analyze.

    .PARAMETER NewStepBlocks
        Array of New-Step block definitions (Start/End).

    .PARAMETER StopStepperLine
        Line number where Stop-Stepper is located.

    .OUTPUTS
        Array of non-resumable code blocks with Lines and IsBeforeStop properties.
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

    # Collection to hold all non-resumable code blocks found
    $nonResumableBlocks = @()

    # Find all Stepper ignore regions (marked by #region Stepper ignore)
    # These regions contain code that should execute every time, even when resuming
    $ignoredRegions = @()
    $inIgnoreRegion = $false
    $regionStart = -1
    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        $line = $ScriptLines[$i].Trim()
        # Found start of an ignore region
        if ($line -match '^\s*#region\s+Stepper\s+ignore') {
            $inIgnoreRegion = $true
            $regionStart = $i
        }
        # Found end of an ignore region
        elseif ($line -match '^\s*#endregion\s+Stepper\s+ignore' -and $inIgnoreRegion) {
            $ignoredRegions += @{
                Start = $regionStart
                End = $i
            }
            $inIgnoreRegion = $false
        }
    }

    # Find all multi-line comment blocks (<# ... #>)
    # Comments shouldn't be flagged as non-resumable code
    $commentBlocks = @()
    $inCommentBlock = $false
    $commentStart = -1
    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        $line = $ScriptLines[$i]
        # Start of a multi-line comment
        if (-not $inCommentBlock -and $line -match '<#') {
            $inCommentBlock = $true
            $commentStart = $i
        }
        # End of a multi-line comment
        if ($inCommentBlock -and $line -match '#>') {
            $commentBlocks += @{
                Start = $commentStart
                End = $i
            }
            $inCommentBlock = $false
        }
    }

    if ($NewStepBlocks.Count -gt 0) {
        # Check code BEFORE the first New-Step block
        # This code will execute on every run, even when resuming
        $firstBlock = $NewStepBlocks[0]
        $blockLines = @()
        for ($j = 0; $j -lt $firstBlock.Start; $j++) {
            # Skip if line is in an ignored region (user explicitly marked it as OK)
            if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $ignoredRegions) {
                continue
            }

            # Skip if line is in a multi-line comment block
            if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $commentBlocks) {
                continue
            }

            $line = $ScriptLines[$j].Trim()
            # Skip comments, empty lines, and common non-executable statements
            # These are declarations/setup that are safe to execute multiple times
            if ($line -and
                $line -notmatch '^\s*#' -and                 # Single-line comments
                $line -notmatch '^\s*\[CmdletBinding\(' -and  # [CmdletBinding()] attribute
                $line -notmatch '^\s*param\s*\(' -and         # param() block
                $line -notmatch '^\s*using\s+(namespace|module|assembly)' -and  # using statements
                $line -notmatch '^\s*\)\s*$' -and             # Closing parenthesis
                $line -ne '.') {                              # Dot sourcing operator
                # This line is potentially non-resumable code
                $blockLines += $j
            }
        }

        if ($blockLines.Count -gt 0) {
            $nonResumableBlocks += @{
                Lines = $blockLines
                IsBeforeStop = $false
            }
        }

        # Check between consecutive New-Step blocks
        for ($i = 0; $i -lt $NewStepBlocks.Count - 1; $i++) {
            $gapStart = $NewStepBlocks[$i].End + 1
            $gapEnd = $NewStepBlocks[$i + 1].Start - 1

            $blockLines = @()
            for ($j = $gapStart; $j -le $gapEnd; $j++) {
                # Skip if line is in an ignored region
                if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $ignoredRegions) {
                    continue
                }

                # Skip if line is in a multi-line comment block
                if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $commentBlocks) {
                    continue
                }

                $line = $ScriptLines[$j].Trim()
                if ($line -and $line -notmatch '^\s*#') {
                    $blockLines += $j
                }
            }

            if ($blockLines.Count -gt 0) {
                $nonResumableBlocks += @{
                    Lines = $blockLines
                    IsBeforeStop = $false
                }
            }
        }

        # Check between last New-Step and Stop-Stepper (or end of file if no Stop-Stepper)
        $lastBlock = $NewStepBlocks[$NewStepBlocks.Count - 1]
        $gapStart = $lastBlock.End + 1
        # If Stop-Stepper exists, check up to it; otherwise check to end of file
        $gapEnd = if ($StopStepperLine -ge 0) { $StopStepperLine - 1 } else { $ScriptLines.Count - 1 }

        $blockLines = @()
        for ($j = $gapStart; $j -le $gapEnd; $j++) {
            # Skip if line is in an ignored region
            if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $ignoredRegions) {
                continue
            }

            # Skip if line is in a multi-line comment block
            if (Test-LineInIgnoredRegion -LineIndex $j -IgnoredRegions $commentBlocks) {
                continue
            }

            $line = $ScriptLines[$j].Trim()
            if ($line -and $line -notmatch '^\s*#') {
                $blockLines += $j
            }
        }

        if ($blockLines.Count -gt 0) {
            $nonResumableBlocks += @{
                Lines = $blockLines
                IsBeforeStop = ($StopStepperLine -ge 0)
            }
        }
    }

    return $nonResumableBlocks
}
