function Invoke-StepperMissingStopRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Issues
    )

    $missingStopIssues = @($Issues | Where-Object Code -EQ 'MissingStopStepper')
    if ($missingStopIssues.Count -eq 0) {
        return New-StepperRemediationResult -Disposition Continue -Message 'No Stop-Stepper remediation is required.'
    }

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    $scriptName = Split-Path -Leaf $ScriptPath
    Write-Host ''
    Write-Host "[!] $scriptName does not call Stop-Stepper." -ForegroundColor Magenta
    Write-Host 'Stop-Stepper removes state after a successful run.'
    Write-Host ''
    Write-Host '  [A] Add Stop-Stepper (Default)' -ForegroundColor Cyan
    Write-Host '  [C] Continue for this invocation only' -ForegroundColor White
    Write-Host '  [Q] Quit' -ForegroundColor White

    $choice = Read-StepperChoice -NonInteractiveDefault 'c'
    $choice = if ($null -eq $choice) { '' } else { $choice.Trim().ToLowerInvariant() }
    switch ($choice) {
        'c' {
            Write-Warning 'Continuing without Stop-Stepper. State will not be removed automatically after success.'
            return New-StepperRemediationResult -Disposition Continue -HandledIssues $missingStopIssues `
                -Message 'Missing Stop-Stepper was waived for this invocation only; validation remains unchanged.'
        }
        'q' {
            return New-StepperRemediationResult -Disposition Quit -HandledIssues $missingStopIssues `
                -Message 'Missing Stop-Stepper remediation was cancelled without changing the script.'
        }
        'a' { }
        '' { }
        default {
            return New-StepperRemediationResult -Disposition Quit -HandledIssues $missingStopIssues `
                -Message 'The choice was not recognized; the script was not changed.'
        }
    }

    $content = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $updatedContent = $content.TrimEnd("`r", "`n")
    if ($updatedContent.Length -gt 0) {
        $updatedContent += "$newline$newline"
    }
    $updatedContent += "Stop-Stepper$newline"

    $transaction = Invoke-StepperRewriteTransaction -ScriptPath $ScriptPath -Content $updatedContent
    New-StepperRemediationResult -Disposition Rerun -HandledIssues $missingStopIssues -Changed $true `
        -BackupPath $transaction.BackupPath `
        -Message "Stop-Stepper was added in one transaction. Re-run $scriptName."
}
