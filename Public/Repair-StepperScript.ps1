function Repair-StepperScript {
    <#
    .SYNOPSIS
        Inspects a script for Stepper convention issues and silently fixes what it can.

    .DESCRIPTION
        Calls Test-StepperScript internally to discover issues, then applies fixes for
        Error-severity and fixable Warning-severity issues:

          MissingCmdletBinding  — inserts [CmdletBinding()] param() block
          MissingInstallGuard   — inserts Install-Module Stepper guard after param()
          MissingCbh            — delegates to Add-StepperCbh (silent)

        The following issues are reported via Write-Warning but NOT automatically fixed:

          MissingStopStepper    — requires author decision on placement
          NoSteps               — empty script structure is intentional or in-progress

        Returns the post-fix result of Test-StepperScript. If no changes were needed,
        the script file is not touched.

        Supports -WhatIf: no file modifications are made when -WhatIf is passed.

    .PARAMETER ScriptPath
        Absolute path to the PowerShell script file to repair.

    .OUTPUTS
        PSCustomObject — the result of Test-StepperScript after repairs are applied.
                         Shape: { Path, IsValid, Issues[] }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Path')]
        [string]$ScriptPath
    )

    $initialResult = Test-StepperScript -ScriptPath $ScriptPath

    $needsFix = $initialResult.Issues | Where-Object {
        $_.Code -in 'MissingCmdletBinding', 'MissingInstallGuard', 'MissingCbh'
    }

    if ($needsFix -and $PSCmdlet.ShouldProcess($ScriptPath, 'Repair Stepper script requirements')) {
        $hasMissingCbh        = $needsFix | Where-Object Code -EQ 'MissingCbh'
        $hasMissingCmdlet     = $needsFix | Where-Object Code -EQ 'MissingCmdletBinding'
        $hasMissingGuard      = $needsFix | Where-Object Code -EQ 'MissingInstallGuard'

        if ($hasMissingCmdlet -or $hasMissingGuard) {
            $scriptLines = Get-Content -Path $ScriptPath -ErrorAction Stop
            $parsedAst   = Get-ScriptAst -ScriptPath $ScriptPath
            $newLines    = @()

            if ($hasMissingCmdlet) {
                # Find insertion point: after leading empty lines, comments, shebang
                $insertIndex = 0
                for ($i = 0; $i -lt $scriptLines.Count; $i++) {
                    $line = $scriptLines[$i].Trim()
                    if ($line -eq '' -or $line -match '^#') {
                        $insertIndex = $i + 1
                    } else {
                        break
                    }
                }

                # Copy leading lines
                for ($i = 0; $i -lt $insertIndex; $i++) {
                    $newLines += $scriptLines[$i]
                }

                # Inject [CmdletBinding()] param()
                $newLines += '[CmdletBinding()]'
                $newLines += 'param()'

                # Inject guard if also missing
                if ($hasMissingGuard) {
                    $newLines += '#region Stepper ignore'
                    $newLines += 'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    $newLines += '#endregion Stepper ignore'
                }

                $newLines += ''

                # Skip existing empty param() block to avoid duplication
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
                    $newLines += $scriptLines[$i]
                }
            } else {
                # [CmdletBinding()] exists but guard is missing — insert after param() block
                $guardInsertIndex = if ($parsedAst.Ast.ParamBlock) {
                    $parsedAst.Ast.ParamBlock.Extent.EndLineNumber
                } else {
                    ($scriptLines | Select-String '\[CmdletBinding' | Select-Object -First 1).LineNumber
                }

                for ($i = 0; $i -lt $guardInsertIndex; $i++) {
                    $newLines += $scriptLines[$i]
                }
                $newLines += '#region Stepper ignore'
                $newLines += 'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                $newLines += '#endregion Stepper ignore'
                for ($i = $guardInsertIndex; $i -lt $scriptLines.Count; $i++) {
                    $newLines += $scriptLines[$i]
                }
            }

            $newLines | Set-Content -Path $ScriptPath -Force -ErrorAction Stop
        }

        if ($hasMissingCbh) {
            Add-StepperCbh -ScriptPath $ScriptPath | Out-Null
        }
    }

    # Emit Write-Warning for non-fixable warnings
    $warnCodes = $initialResult.Issues |
        Where-Object { $_.Code -in 'MissingStopStepper', 'NoSteps' }

    foreach ($w in $warnCodes) {
        Write-Warning $w.Message
    }

    # Return post-fix result
    Test-StepperScript -ScriptPath $ScriptPath
}
