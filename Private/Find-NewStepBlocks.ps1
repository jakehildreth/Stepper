function Find-NewStepBlocks {
    <#
    .SYNOPSIS
        Finds all New-Step blocks and Stop-Stepper line in a script.

    .PARAMETER ScriptLines
        Array of script lines to analyze.

    .OUTPUTS
        Hashtable with NewStepBlocks array and StopStepperLine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScriptLines
    )

    $newStepBlocks = @()
    $stopStepperLine = -1

    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        if ($ScriptLines[$i] -match '^\s*New-Step\s+\{') {
            # Find the closing brace for this New-Step block
            $braceCount = 0
            $blockStart = $i
            $blockEnd = -1

            for ($j = $i; $j -lt $ScriptLines.Count; $j++) {
                $line = $ScriptLines[$j]
                $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                if ($braceCount -eq 0 -and $j -gt $i) {
                    $blockEnd = $j
                    break
                }
            }

            if ($blockEnd -ge 0) {
                $newStepBlocks += @{
                    Start = $blockStart
                    End = $blockEnd
                }
            }
        }
        if ($ScriptLines[$i] -match '^\s*Stop-Stepper') {
            $stopStepperLine = $i
            break
        }
    }

    return @{
        NewStepBlocks = $newStepBlocks
        StopStepperLine = $stopStepperLine
    }
}
