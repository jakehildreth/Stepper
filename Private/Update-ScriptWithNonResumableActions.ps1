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
    $linesToWrap = @()
    $linesToMove = @()
    $lastBlock = $NewStepBlocks[$NewStepBlocks.Count - 1]

    # Separate lines by action
    foreach ($lineIdx in $Actions.Keys) {
        switch ($Actions[$lineIdx].Action) {
            'Wrap' { $linesToWrap += $lineIdx }
            'Move' { $linesToMove += $lineIdx }
        }
    }

    # Copy all lines except ones being removed
    for ($i = 0; $i -lt $ScriptLines.Count; $i++) {
        if (-not $Actions.ContainsKey($i)) {
            $newScriptLines += $ScriptLines[$i]
        }

        # After the last New-Step block, add wrapped code
        if ($i -eq $lastBlock.End -and $linesToWrap.Count -gt 0) {
            $newScriptLines += ""
            $newScriptLines += "New-Step {"
            foreach ($lineIdx in ($linesToWrap | Sort-Object)) {
                $newScriptLines += "    $($ScriptLines[$lineIdx])"
            }
            $newScriptLines += "}"
        }
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
