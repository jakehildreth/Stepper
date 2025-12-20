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

    $nonResumableBlocks = @()

    if ($NewStepBlocks.Count -gt 0) {
        # Check code BEFORE the first New-Step block
        $firstBlock = $NewStepBlocks[0]
        $blockLines = @()
        for ($j = 0; $j -lt $firstBlock.Start; $j++) {
            $line = $ScriptLines[$j].Trim()
            # Skip comments, empty lines, and common non-executable statements
            if ($line -and 
                $line -notmatch '^\s*#' -and 
                $line -notmatch '^\s*<#' -and
                $line -notmatch '^\s*#>' -and
                $line -notmatch '^\s*\.SYNOPSIS' -and
                $line -notmatch '^\s*\.DESCRIPTION' -and
                $line -notmatch '^\s*\.NOTES' -and
                $line -notmatch '^\s*\.EXAMPLE' -and
                $line -notmatch '^\s*\.PARAMETER' -and
                $line -notmatch '^\s*\[CmdletBinding\(' -and
                $line -notmatch '^\s*param\s*\(' -and
                $line -notmatch '^\s*using\s+(namespace|module|assembly)' -and
                $line -notmatch '^\s*\)\s*$' -and
                $line -ne '.') {
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

        # Check between last New-Step and Stop-Stepper
        if ($StopStepperLine -ge 0) {
            $lastBlock = $NewStepBlocks[$NewStepBlocks.Count - 1]
            $gapStart = $lastBlock.End + 1
            $gapEnd = $StopStepperLine - 1

            $blockLines = @()
            for ($j = $gapStart; $j -le $gapEnd; $j++) {
                $line = $ScriptLines[$j].Trim()
                if ($line -and $line -notmatch '^\s*#') {
                    $blockLines += $j
                }
            }

            if ($blockLines.Count -gt 0) {
                $nonResumableBlocks += @{
                    Lines = $blockLines
                    IsBeforeStop = $true
                }
            }
        }
    }

    return $nonResumableBlocks
}
