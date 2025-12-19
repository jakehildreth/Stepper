function Update-ScriptWithNonResumableActions {
    <#
    .SYNOPSIS
        Applies wrap/move/delete actions to a script.

    .PARAMETER ScriptPath
        Path to the script file to update.

    .PARAMETER ScriptLines
        Array of script lines.

    .PARAMETER Actions
        Hashtable mapping line indices to actions (Wrap/Move/Delete).

    .PARAMETER NewStepBlocks
        Array of New-Step block definitions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScriptLines,

        [Parameter(Mandatory)]
        [hashtable]$Actions,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$NewStepBlocks
    )

    $newScriptLines = @()
    $linesToMove = @()
    $lastBlock = $NewStepBlocks[$NewStepBlocks.Count - 1]

    # Group lines to wrap by consecutive sequences
    $linesToWrap = @($Actions.Keys | Where-Object { $Actions[$_].Action -eq 'Wrap' } | Sort-Object)
    $wrapGroups = @()
    if ($linesToWrap.Count -gt 0) {
        $currentGroup = @($linesToWrap[0])
        for ($i = 1; $i -lt $linesToWrap.Count; $i++) {
            if ($linesToWrap[$i] -eq $linesToWrap[$i - 1] + 1) {
                $currentGroup += $linesToWrap[$i]
            } else {
                $wrapGroups += ,@($currentGroup)
                $currentGroup = @($linesToWrap[$i])
            }
        }
        $wrapGroups += ,@($currentGroup)
    }

    # Separate lines to move
    foreach ($lineIdx in $Actions.Keys) {
        if ($Actions[$lineIdx].Action -eq 'Move') {
            $linesToMove += $lineIdx
        }
    }

    # Process all lines
    $wrappedLines = @{}
    foreach ($group in $wrapGroups) {
        foreach ($idx in $group) {
            $wrappedLines[$idx] = $true
        }
    }

    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        # Check if this line starts a wrap group
        $startsWrapGroup = $false
        $wrapGroup = $null
        foreach ($group in $wrapGroups) {
            if ($group[0] -eq $i) {
                $startsWrapGroup = $true
                $wrapGroup = $group
                break
            }
        }

        if ($startsWrapGroup) {
            # Start the New-Step block
            $newScriptLines += "New-Step {"
            foreach ($idx in $wrapGroup) {
                $newScriptLines += "    $($ScriptLines[$idx])"
            }
            $newScriptLines += "}"
            # Skip to after this group
            $i = $wrapGroup[-1]
            continue
        }

        # Skip lines that are wrapped (but not the start of a group) or moved or deleted
        if ($wrappedLines.ContainsKey($i) -or 
            ($Actions.ContainsKey($i) -and $Actions[$i].Action -in @('Move', 'Delete'))) {
            continue
        }

        # Copy line as-is
        $newScriptLines += $ScriptLines[$i]
    }

    # Add moved code at the end
    if ($linesToMove.Count -gt 0) {
        $newScriptLines += ""
        foreach ($lineIdx in ($linesToMove | Sort-Object)) {
            $newScriptLines += $ScriptLines[$lineIdx]
        }
    }

    # Write back to file
    $newScriptLines | Set-Content -Path $ScriptPath -Force
    Write-Host ""
    Write-Host "Changes applied. Please re-run the script." -ForegroundColor Green
}
