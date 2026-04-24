function Test-StepperScriptRequirements {
    <#
    .SYNOPSIS
        Checks if a script has a [CmdletBinding()] declaration and silently adds it if missing.

    .PARAMETER ScriptPath
        Path to the script to check.

    .OUTPUTS
        $true if the script was modified and needs to be re-run, $false otherwise.
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

    $needsChanges = -not $hasCmdletBinding

    if ($needsChanges) {
        $newScriptLines = @()
        $addedDeclarations = $false

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

            # Add missing [CmdletBinding()]
            $newScriptLines += "[CmdletBinding()]"
            $newScriptLines += "param()"
            $newScriptLines += "if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }"
            $addedDeclarations = $true
            Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Added missing '[CmdletBinding()]' and Stepper install guard to $scriptName"

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
            Write-Host "[+] Stepper updated $scriptName with required declarations:" -ForegroundColor Cyan
            Write-Host "      Added: [CmdletBinding()] param()" -ForegroundColor Gray
            Write-Host "      Added: Install-Module Stepper guard (runs only if not installed)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "[>] Please re-run your script to continue." -ForegroundColor Yellow
            Write-Host ""

            return $true
    }

    return $false
}
