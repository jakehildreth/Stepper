function Test-StepperScriptRequirements {
    <#
    .SYNOPSIS
        Checks if a script has [CmdletBinding()] and the Stepper self-install guard, and silently adds either if missing.

    .PARAMETER ScriptPath
        Path to the script to check.

    .PARAMETER LogPath
        Path to the Stepper log file. Defaults to ScriptPath + '.stepper.log'.

    .OUTPUTS
        $true if the script was modified and needs to be re-run, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter()]
        [string]$LogPath
    )

    if (-not $LogPath) {
        $LogPath = $ScriptPath + '.stepper.log'
    }

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

    $hasInstallGuard = $scriptLines | Where-Object { $_ -match 'Install-Module\s+Stepper' }
    $needsChanges = -not $hasCmdletBinding -or -not $hasInstallGuard

    if ($needsChanges) {
        $newScriptLines = @()

        if (-not $hasCmdletBinding) {
            # Find where to insert (after shebang/comments at top, before first code)
            $insertIndex = 0
            for ($i = 0; $i -lt $scriptLines.Count; $i++) {
                $line = $scriptLines[$i].Trim()
                # Skip empty lines, comments, and shebang
                if ($line -eq '' -or $line -match '^#' -or $line -match '^#!/') {
                    $insertIndex = $i + 1
                } else {
                    break
                }
            }

            # Copy lines before insertion point
            for ($i = 0; $i -lt $insertIndex; $i++) {
                $newScriptLines += $scriptLines[$i]
            }

            # Add missing [CmdletBinding()] and guard (only inject guard if not already present)
            $newScriptLines += "[CmdletBinding()]"
            $newScriptLines += "param()"
            if (-not $hasInstallGuard) {
                $newScriptLines += "#region Stepper ignore"
                $newScriptLines += "if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }"
                $newScriptLines += "#endregion Stepper ignore"
            }
            $newScriptLines += ""
            Write-StepperLog -Message "Added missing '[CmdletBinding()]' and Stepper install guard to $scriptName" -LogPath $LogPath

            # Copy remaining lines, skipping the existing empty param() block if we added one.
            # Use AST extent to handle both single-line and multi-line empty param blocks.
            $existingParamStart = -1
            $existingParamEnd   = -1
            if ($parsedAst.Ast.ParamBlock -and
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
        } else {
            # [CmdletBinding()] exists but guard is missing — insert guard after param() block
            $guardInsertIndex = if ($parsedAst.Ast.ParamBlock) {
                $parsedAst.Ast.ParamBlock.Extent.EndLineNumber
            } else {
                ($scriptLines | Select-String '\[CmdletBinding' | Select-Object -First 1).LineNumber
            }

            for ($i = 0; $i -lt $guardInsertIndex; $i++) {
                $newScriptLines += $scriptLines[$i]
            }
            $newScriptLines += "#region Stepper ignore"
            $newScriptLines += "if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }"
            $newScriptLines += "#endregion Stepper ignore"
            for ($i = $guardInsertIndex; $i -lt $scriptLines.Count; $i++) {
                $newScriptLines += $scriptLines[$i]
            }
            Write-StepperLog -Message "Added missing Stepper install guard to $scriptName" -LogPath $LogPath
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
        Write-Host "[+] Stepper updated $scriptName with required declarations:" -ForegroundColor Cyan
        if (-not $hasCmdletBinding) {
            Write-Host "      Added: [CmdletBinding()] param()" -ForegroundColor Gray
        }
        Write-Host "      Added: Install-Module Stepper guard (runs only if not installed)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[>] Please re-run your script to continue." -ForegroundColor Yellow
        Write-Host ""

        return $true
    }

    return $false
}
