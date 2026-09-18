function Invoke-StepperUnmanagedCodeRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Issues
    )

    $unmanagedIssues = @($Issues | Where-Object Code -EQ 'UnmanagedCode' | Sort-Object { $_.Location.StartLine }, { $_.Location.StartColumn })
    $noSteps = @($Issues | Where-Object Code -EQ 'NoSteps').Count -gt 0

    if ($unmanagedIssues.Count -eq 0) {
        return New-StepperRemediationResult -Disposition Continue -Message 'No unmanaged code remediation is required.'
    }

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    $content = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lineStarts = [System.Collections.Generic.List[int]]::new()
    $lineStarts.Add(0)
    for ($index = 0; $index -lt $content.Length; $index++) {
        if ($content[$index] -eq "`r") {
            if ($index + 1 -lt $content.Length -and $content[$index + 1] -eq "`n") {
                $index++
            }
            $lineStarts.Add($index + 1)
        }
        elseif ($content[$index] -eq "`n") {
            $lineStarts.Add($index + 1)
        }
    }

    if ($noSteps) {
        Write-Host ''
        Write-Host '[!] This script has no New-Step calls.' -ForegroundColor Magenta
        Write-Host 'Wrapping unmanaged code can create the required first unnamed step.' -ForegroundColor Yellow
        Write-Host 'Other choices may leave the NoSteps error unresolved.' -ForegroundColor Yellow
    }

    $decisions = [System.Collections.Generic.List[object]]::new()
    foreach ($issue in $unmanagedIssues) {
        $location = $issue.Location
        Write-Host ''
        Write-Host ("[!] Unmanaged code at lines {0}-{1}:" -f $location.StartLine, $location.EndLine) -ForegroundColor Magenta
        Write-Host $location.Text -ForegroundColor Gray
        Write-Host ''
        Write-Host '  [W] Wrap in an unnamed New-Step (Default)' -ForegroundColor Cyan
        Write-Host '  [M] Mark ignored' -ForegroundColor White
        Write-Host '  [D] Delete' -ForegroundColor White
        Write-Host '  [I] Ignore for this invocation only' -ForegroundColor White
        Write-Host '  [Q] Quit without applying any decisions' -ForegroundColor White

        $choice = Read-StepperChoice -NonInteractiveDefault 'w'
        $choice = if ($null -eq $choice) { '' } else { $choice.Trim().ToLowerInvariant() }
        switch ($choice) {
            'q' {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $unmanagedIssues `
                    -Message 'Unmanaged-code remediation was cancelled without changing the script.'
            }
            'm' { $action = 'MarkIgnored' }
            'd' { $action = 'Delete' }
            'i' { $action = 'Ignore' }
            'w' { $action = 'Wrap' }
            '' { $action = 'Wrap' }
            default {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $unmanagedIssues `
                    -Message 'The choice was not recognized; no unmanaged-code decisions were applied.'
            }
        }

        $decisions.Add([PSCustomObject]@{
            Issue  = $issue
            Action = $action
        })
    }

    $mutations = @($decisions | Where-Object Action -NE 'Ignore')
    if ($mutations.Count -eq 0) {
        return New-StepperRemediationResult -Disposition Continue -HandledIssues $unmanagedIssues `
            -Message 'Unmanaged-code findings were waived for this invocation only; validation remains unchanged.'
    }

    $edits = [System.Collections.Generic.List[object]]::new()
    foreach ($decision in $mutations) {
        $location = $decision.Issue.Location
        $startOffset = $lineStarts[$location.StartLine - 1] + $location.StartColumn - 1
        $endOffset = $lineStarts[$location.EndLine - 1] + $location.EndColumn - 1
        $sourceText = $content.Substring($startOffset, $endOffset - $startOffset)

        switch ($decision.Action) {
            'Wrap' {
                $indented = (($sourceText -split '\r\n|\n|\r') | ForEach-Object {
                    if ($_.Length -eq 0) { '' } else { "    $_" }
                }) -join $newline
                $replacement = "New-Step {$newline$indented$newline}"
            }
            'MarkIgnored' {
                $replacement = "#region Stepper ignore$newline$sourceText$newline#endregion Stepper ignore"
            }
            'Delete' {
                $replacement = ''
            }
        }

        $edits.Add([PSCustomObject]@{
            StartOffset = $startOffset
            EndOffset   = $endOffset
            Replacement = $replacement
        })
    }

    $updatedContent = $content
    foreach ($edit in @($edits | Sort-Object StartOffset -Descending)) {
        $updatedContent = $updatedContent.Substring(0, $edit.StartOffset) +
            $edit.Replacement +
            $updatedContent.Substring($edit.EndOffset)
    }

    $transaction = Invoke-StepperRewriteTransaction -ScriptPath $ScriptPath -Content $updatedContent
    New-StepperRemediationResult -Disposition Rerun -HandledIssues $unmanagedIssues -Changed $true `
        -BackupPath $transaction.BackupPath `
        -Message "Unmanaged code was rewritten in one transaction. Re-run $(Split-Path -Leaf $ScriptPath)."
}
