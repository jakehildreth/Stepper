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

    try {
        $scriptLines = Get-Content -Path $ScriptPath -ErrorAction Stop
    }
    catch {
        $exception = [System.IO.IOException]::new("Failed to read script file '$ScriptPath'", $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'ScriptReadFailed',
            [System.Management.Automation.ErrorCategory]::ReadError,
            $ScriptPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    $scriptName = Split-Path $ScriptPath -Leaf

    # Parse via AST for accurate structural detection
    $parsedAst = Get-ScriptAst -ScriptPath $ScriptPath

    # Check for [CmdletBinding()] on the ParamBlock
    $hasCmdletBinding = $parsedAst.Ast.ParamBlock -and
        ($parsedAst.Ast.ParamBlock.Attributes |
            Where-Object { $_.TypeName.Name -eq 'CmdletBinding' })

    # Check for #requires -Modules Stepper
    $hasRequires = $parsedAst.Ast.ScriptRequirements -and
        ($parsedAst.Ast.ScriptRequirements.RequiredModules |
            Where-Object { $_.Name -eq 'Stepper' })

    $needsChanges = -not $hasCmdletBinding -or -not $hasRequires

    if ($needsChanges) {
        Write-Host ""
        Write-Host "[!] Script requirements check for ${scriptName}:" -ForegroundColor Magenta
        Write-Host ""

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
        try {
            $response = Read-Host
        }
        catch {
            # Non-interactive context - default to Add (safer for automation)
            $response = 'a'
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to Add"
        }

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

            # Copy remaining lines, skipping the existing empty param() block if we added one.
            # Use AST extent to handle both single-line and multi-line empty param blocks.
            $existingParamStart = -1
            $existingParamEnd   = -1
            if (-not $hasCmdletBinding -and
                $parsedAst.Ast.ParamBlock -and
                $parsedAst.Ast.ParamBlock.Parameters.Count -eq 0) {
                $existingParamStart = $parsedAst.Ast.ParamBlock.Extent.StartLineNumber - 1
                $existingParamEnd   = $parsedAst.Ast.ParamBlock.Extent.EndLineNumber - 1
            }
            for ($i = $insertIndex; $i -lt $scriptLines.Count; $i++) {
                if ($existingParamStart -ge 0 -and
                    $i -ge $existingParamStart -and
                    $i -le $existingParamEnd) {
                    continue
                }
                $newScriptLines += $scriptLines[$i]
            }

            # Write back to file
            try {
                $newScriptLines | Set-Content -Path $ScriptPath -Force -ErrorAction Stop
            }
            catch {
                $exception = [System.IO.IOException]::new("Failed to write to script file '$ScriptPath'", $_.Exception)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'ScriptWriteFailed',
                    [System.Management.Automation.ErrorCategory]::WriteError,
                    $ScriptPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }

            # Delete state file since script was modified
            $statePath = Get-StepperStatePath -ScriptPath $ScriptPath
            Remove-StepperState -StatePath $statePath

            Write-Host ""
            Write-Host "Declarations added. Please re-run $scriptName." -ForegroundColor Green
            return $true
        }
    }

    return $false
}
