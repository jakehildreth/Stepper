function Show-MoreDetails {
    <#
    .SYNOPSIS
        Displays detailed state and script context for an incomplete run.

    .PARAMETER ExistingState
        The object returned by Read-StepperState.

    .PARAMETER ScriptPath
        Path to the current script.

    .PARAMETER CurrentHash
        The current script hash.

    .PARAMETER LastStep
        Identifier of the last completed step (format: "path:line").

    .PARAMETER NextStepLine
        Line number where the next step will execute.

    .PARAMETER ShowHashComparison
        If set, prints both previous and current script hashes (used when script differs).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$ExistingState,
        [Parameter(Mandatory)] [string]$ScriptPath,
        [Parameter(Mandatory)] [string]$CurrentHash,
        [Parameter(Mandatory)] [string]$LastStep,
        [Parameter(Mandatory)] [int]$NextStepLine,
        [switch]$ShowHashComparison
    )

    Write-Host ""
    Write-Host "More details:" -ForegroundColor Yellow
    Write-Host ""
    if ($ShowHashComparison) {
        Write-Host "  Previous script hash: $($ExistingState.ScriptHash)"
    }
    Write-Host "  Current script hash: $CurrentHash"

    # Show Stepper variables and their contents
    Write-Host ""
    Write-Host "Stepper variables:"
    Write-Host ""
    if ($ExistingState.StepperData -and $ExistingState.StepperData.Count -gt 0) {
        foreach ($var in ($ExistingState.StepperData.Keys | Sort-Object)) {
            $val = $ExistingState.StepperData[$var]
            try {
                $valStr = $val | ConvertTo-Json -Depth 4 -ErrorAction Stop
            } catch {
                $valStr = ($val | Out-String).TrimEnd()
            }

            if ($valStr -match "`n") {
                Write-Host ("  {0}:" -f $var)
                $valStr -split "`n" | ForEach-Object { Write-Host "        $_" }
            } else {
                Write-Host ("  {0}: {1}" -f $var, $valStr)
            }
        }
    } else {
        Write-Host "      None"
    }

    # Show full contents of the last completed New-Step using saved script contents if available
    Write-Host ""
    Write-Host "Last completed step:"
    Write-Host ""
    if ($ExistingState.ScriptContents) {
        $prevLines = $ExistingState.ScriptContents -split "`n"
        $prevStepLine = $null
        if ($LastStep -and ($LastStep -match ':(\d+)$')) {
            $prevStepLine = [int]$Matches[1]
        } else {
            Write-Host "  No valid LastCompletedStep recorded." -ForegroundColor Yellow
        }

        # Attempt to extract the full New-Step block using PowerShell's AST,
        # so that braces inside strings or comments don't confuse the logic.
        $block = @()
        $tokens = $null
        $parseErrors = $null
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $ExistingState.ScriptContents,
            [ref]$tokens,
            [ref]$parseErrors
        )

        if (-not $parseErrors -or $parseErrors.Count -eq 0) {
            # Find the New-Step command that contains the previous step line, then get its script-block argument
            $cmdAst = $scriptAst.Find(
                {
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    ($node.GetCommandName() -eq 'New-Step') -and
                    $node.Extent.StartLineNumber -le $prevStepLine -and
                    $node.Extent.EndLineNumber -ge $prevStepLine
                },
                $true
            )

            # Collect all New-Step commands with scriptblock arguments
            $cmdList = $scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and ($node.GetCommandName() -eq 'New-Step') }, $true) |
                      ForEach-Object {
                          $sb = $_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockAst] } | Select-Object -First 1
                          if ($sb) {
                              [pscustomobject]@{
                                  Command = $_
                                  ScriptBlock = $sb
                                  Start = $sb.Extent.StartLineNumber
                                  End = $sb.Extent.EndLineNumber
                                  CmdStart = $_.Extent.StartLineNumber
                                  CmdEnd = $_.Extent.EndLineNumber
                              }
                          }
                      }

            $scriptBlockAst = $null

            # Prefer a scriptblock that actually spans the previous step line
            $candidate = $cmdList | Where-Object { $_.Start -le $prevStepLine -and $_.End -ge $prevStepLine } | Select-Object -First 1

            # If none span the line, prefer a command whose declaration line matches the step line
            if (-not $candidate) {
                $candidate = $cmdList | Where-Object { $_.CmdStart -eq $prevStepLine } | Select-Object -First 1
            }

            # If still none, pick the closest preceding scriptblock (highest Start <= prevStepLine)
            if (-not $candidate) {
                $candidate = $cmdList | Where-Object { $_.Start -lt $prevStepLine } | Sort-Object -Property Start -Descending | Select-Object -First 1
            }

            if ($candidate) {
                $scriptBlockAst = $candidate.ScriptBlock
                $startLine = $candidate.Start
                $endLine = $candidate.End

                for ($i = $startLine; $i -le $endLine -and $i -le $prevLines.Count; $i++) {
                    $block += $prevLines[$i - 1]
                }
            } else {
                Write-Verbose "Show-MoreDetails: AST lookup failed for New-Step around line $prevStepLine; attempting manual brace-match fallback"

                # Search upward for the nearest 'New-Step {' start line
                $foundStart = $null
                for ($s = $prevStepLine; $s -ge 1; $s--) {
                    if ($prevLines[$s - 1] -match '^\s*New-Step\s*\{') {
                        $foundStart = $s
                        break
                    }
                }

                if ($foundStart) {
                    $level = 0
                    $endLine = $foundStart

                    for ($i = $foundStart; $i -le $prevLines.Count; $i++) {
                        $lineText = $prevLines[$i - 1]

                        # Strip simple quoted strings to reduce brace noise
                        $stripped = $lineText -replace "'[^']*'", '' -replace '"[^"]*"', ''

                        $opens = ($stripped -split '{').Count - 1
                        $closes = ($stripped -split '}').Count - 1
                        $level += $opens - $closes

                        if ($level -le 0) {
                            $endLine = $i
                            break
                        }
                    }

                    if ($endLine -ge $foundStart) {
                        for ($i = $foundStart; $i -le $endLine -and $i -le $prevLines.Count; $i++) {
                            $block += $prevLines[$i - 1]
                        }
                    }
                    else {
                        Write-Verbose "Show-MoreDetails: Manual brace-match failed to find end for New-Step starting at $foundStart"
                    }
                }
                else {
                    Write-Verbose "Show-MoreDetails: No 'New-Step {' found above line $prevStepLine"
                }
            }
        }

        if ($block.Count -gt 0) {
            $block | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "  Unable to extract step body." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  No saved script contents available." -ForegroundColor Yellow
    }

    # Show context around the restart line in the current script (2 lines before / 3 lines after)
    Write-Host ""
    Write-Host "Context around next restart line:"
    Write-Host ""
    $ns = [int]$NextStepLine
    $start2 = [Math]::Max(1, $ns - 2)
    $end2 = $ns + 3

    # Read only as many lines as we need for context, instead of the entire file
    $contextLines = Get-Content -Path $ScriptPath -TotalCount $end2
    $lastLineToShow = [Math]::Min($end2, $contextLines.Count)

    for ($ln = $start2; $ln -le $lastLineToShow; $ln++) {
        $line = $contextLines[$ln - 1]
        $display = ($line -replace "`t", "    ").TrimEnd()
        if ($ln -eq $ns) {
            Write-Host ("{0,5}: {1}" -f $ln, $display) -ForegroundColor Cyan
        } else {
            Write-Host ("{0,5}: {1}" -f $ln, $display)
        }
    }

    Write-Host ""

    # Prompt header for available actions
    Write-Host "How would you like to proceed?"
    Write-Host ""
}
