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
        Write-Host "  Current script hash:  $CurrentHash"
    }
    Write-Host "  Script hash: $($ExistingState.ScriptHash)"

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
        $prevStepLine = ($LastStep -split ':')[-1] -as [int]

        # Attempt to extract the full New-Step block by matching braces
        $block = @()
        $depth = 0
        $started = $false
        for ($i = $prevStepLine - 1; $i -lt $prevLines.Count; $i++) {
            $lineText = $prevLines[$i]
            $openCount = ([regex]::Matches($lineText, '\{')).Count
            $closeCount = ([regex]::Matches($lineText, '\}')).Count

            if (-not $started -and $openCount -gt 0) {
                $started = $true
            }
            if ($started) {
                $block += $lineText
                $depth += $openCount - $closeCount
                if ($depth -le 0) { break }
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
