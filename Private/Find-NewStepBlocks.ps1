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

    # Initialize collection for New-Step blocks found in the script
    $newStepBlocks = @()
    # Track where Stop-Stepper is located (-1 means not found yet)
    $stopStepperLine = -1

    # Scan through each line of the script
    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        # Look for lines that start a New-Step block (e.g., "New-Step {")
        if ($ScriptLines[$i] -match '^\s*New-Step\s+\{') {
            # Find the closing brace for this New-Step block
            # PowerShell blocks can contain nested braces, so we count them
            $braceCount = 0
            $blockStart = $i
            $blockEnd = -1

            # Walk through lines starting from current position
            for ($j = $i; $j -lt $ScriptLines.Count; $j++) {
                $line = $ScriptLines[$j]
                # Count opening braces on this line
                $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
                # Subtract closing braces on this line
                $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count

                # When brace count returns to 0, we found the matching closing brace
                # ($j -gt $i ensures we don't stop on the opening line)
                if ($braceCount -eq 0 -and $j -gt $i) {
                    $blockEnd = $j
                    break
                }
            }

            # If we found a complete block, add it to our collection
            if ($blockEnd -ge 0) {
                $newStepBlocks += @{
                    Start = $blockStart  # Line where "New-Step {" appears
                    End = $blockEnd      # Line where the matching "}" appears
                }
            }
        }
        # Look for Stop-Stepper call (signals end of steps)
        if ($ScriptLines[$i] -match '^\s*Stop-Stepper') {
            $stopStepperLine = $i
            break  # Stop scanning once we find Stop-Stepper
        }
    }

    # Return hashtable with both pieces of information
    return @{
        NewStepBlocks = $newStepBlocks    # Array of block boundaries
        StopStepperLine = $stopStepperLine  # Line number or -1
    }
}
