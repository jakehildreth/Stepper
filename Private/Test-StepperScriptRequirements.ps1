function Test-StepperScriptRequirements {
    <#
    .SYNOPSIS
        Checks if script has required declarations and offers to add them.

    .PARAMETER ScriptPath
        Path to the script to check.

    .OUTPUTS
        $true if script was modified and needs to be re-run, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )

    $scriptLines = Get-Content -Path $ScriptPath
    $scriptName = Split-Path $ScriptPath -Leaf

    # Check for CmdletBinding
    $hasCmdletBinding = $scriptLines | Where-Object { $_ -match '^\s*\[CmdletBinding\(\)\]' }

    # Check for #requires statement (case-insensitive)
    $hasRequires = $scriptLines | Where-Object { $_ -match '(?i)^\s*#requires\s+-Modules?\s+Stepper' }

    $needsChanges = -not $hasCmdletBinding -or -not $hasRequires

    if ($needsChanges) {
        Write-Host ""
        Write-Host "[!] Script requirements check for ${scriptName}:" -ForegroundColor Magenta

        if (-not $hasCmdletBinding) {
            Write-Host "  Missing [CmdletBinding()] declaration" -ForegroundColor Gray
        }

        if (-not $hasRequires) {
            Write-Host "  Missing #requires -Modules Stepper statement" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "How would you like to handle this?"
        Write-Host ""
        Write-Host "  [A] Add missing declarations (Default)" -ForegroundColor Cyan
        Write-Host "  [S] Skip" -ForegroundColor White
        Write-Host "  [Q] Quit" -ForegroundColor White
        Write-Host ""
        Write-Host "Choice? [" -NoNewline
        Write-Host "A" -NoNewline -ForegroundColor Cyan
        Write-Host "/s/q]: " -NoNewline
        $response = Read-Host

        if ($response -eq 'Q' -or $response -eq 'q') {
            Write-Host ""
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit
        }

        if ($response -eq '' -or $response -eq 'A' -or $response -eq 'a') {
            $newScriptLines = @()
            $addedDeclarations = $false

            # Find where to insert (after shebang/comments at top, before first code)
            $insertIndex = 0
            for ($i = 0; $i -lt $scriptLines.Count; $i++) {
                $line = $scriptLines[$i].Trim()
                # Skip empty lines, comments (but not #requires), and shebang
                if ($line -eq '' -or $line -match '^#(?!requires)' -or $line -match '^#!/') {
                    $insertIndex = $i + 1
                } else {
                    break
                }
            }

            # Copy lines before insertion point
            for ($i = 0; $i -lt $insertIndex; $i++) {
                $newScriptLines += $scriptLines[$i]
            }

            # Add missing declarations
            if (-not $hasRequires) {
                $newScriptLines += "#requires -Modules Stepper"
                $addedDeclarations = $true
            }

            if (-not $hasCmdletBinding) {
                $newScriptLines += "[CmdletBinding()]"
                $newScriptLines += "param()"
                $addedDeclarations = $true
            }

            if ($addedDeclarations) {
                $newScriptLines += ""
            }

            # Copy remaining lines, but skip existing param() if we added one
            $skipNextParam = (-not $hasCmdletBinding)
            for ($i = $insertIndex; $i -lt $scriptLines.Count; $i++) {
                if ($skipNextParam -and $scriptLines[$i] -match '^\s*param\s*\(\s*\)\s*$') {
                    $skipNextParam = $false
                    continue
                }
                $newScriptLines += $scriptLines[$i]
            }

            # Write back to file
            $newScriptLines | Set-Content -Path $ScriptPath -Force
            Write-Host ""
            Write-Host "Declarations added to $scriptName. Please re-run the script." -ForegroundColor Green
            return $true
        }
    }

    return $false
}
