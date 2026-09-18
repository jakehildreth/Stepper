function Invoke-StepperLifecycleRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Issues
    )

    $lifecycleCodes = @(
        'DuplicateStartStepper',
        'NestedStartStepper',
        'StartOutsideBootstrapRegion',
        'StartBeforeInstallGuard',
        'StartAfterExecutableCode'
    )
    $handledIssues = @($Issues | Where-Object Code -In $lifecycleCodes)
    if ($handledIssues.Count -eq 0) {
        return New-StepperRemediationResult -Disposition Continue -Message 'No Start-Stepper lifecycle remediation is required.'
    }

    $ScriptPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ScriptPath)
    $content = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop
    $parsed = Get-ScriptAst -ScriptPath $ScriptPath -WarningAction SilentlyContinue
    $ast = $parsed.Ast
    $rootStatements = @($ast.EndBlock.Statements)
    $commands = @($ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        $name = $node.GetCommandName()
        if ($name) { $name = ($name -split '\\')[-1] }
        return $name -in 'Start-Stepper', 'Initialize-Stepper'
    }, $true) | Sort-Object { $_.Extent.StartOffset })

    $blockingCodes = @(
        'ParseError',
        'MissingInstallGuard',
        'InvalidInstallGuard',
        'MisplacedInstallGuard',
        'MissingBootstrapRegion',
        'MalformedIgnoreRegion'
    )
    $destinationUnavailable = @($Issues | Where-Object Code -In $blockingCodes).Count -gt 0
    $guard = $null
    $bootstrapRegion = $null

    if (-not $destinationUnavailable) {
        $installCalls = @($ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.CommandAst] -or
                (($node.GetCommandName() -split '\\')[-1]) -ne 'Install-Module') {
                return $false
            }
            $values = @($node.CommandElements | ForEach-Object {
                if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $_.Value }
            })
            return $values -contains 'Stepper'
        }, $true))

        foreach ($installCall in $installCalls) {
            $owner = $installCall.Parent
            while ($owner -and $owner -isnot [System.Management.Automation.Language.IfStatementAst]) {
                $owner = $owner.Parent
            }
            if ($owner -and $rootStatements -contains $owner) {
                $guard = $owner
                break
            }
        }

        $regionStack = [System.Collections.Generic.Stack[object]]::new()
        foreach ($token in @($parsed.Tokens | Where-Object Kind -EQ ([System.Management.Automation.Language.TokenKind]::Comment))) {
            $text = $token.Text.Trim()
            if ($text -match '(?i)^#region\s+Stepper\s+ignore\s*$') {
                $regionStack.Push($token)
            }
            elseif ($text -match '(?i)^#endregion\s+Stepper\s+ignore\s*$' -and $regionStack.Count -gt 0) {
                $startToken = $regionStack.Pop()
                if ($guard -and
                    $guard.Extent.StartOffset -gt $startToken.Extent.EndOffset -and
                    $guard.Extent.EndOffset -lt $token.Extent.StartOffset) {
                    $bootstrapRegion = [PSCustomObject]@{
                        StartOffset = $startToken.Extent.StartOffset
                        EndOffset   = $token.Extent.EndOffset
                        EndLine     = $token.Extent.StartLineNumber
                    }
                    break
                }
            }
        }

        if (-not $guard -or -not $bootstrapRegion) {
            $destinationUnavailable = $true
        }
    }

    $scriptName = Split-Path -Leaf $ScriptPath
    Write-Host ''
    Write-Host "[!] Start-Stepper lifecycle calls require remediation in $scriptName." -ForegroundColor Magenta
    foreach ($command in $commands) {
        Write-Host ("  {0}: {1}" -f $command.Extent.StartLineNumber, $command.Extent.Text.Trim()) -ForegroundColor Gray
    }
    if ($destinationUnavailable) {
        Write-Host 'The canonical destination is unavailable until the bootstrap structure is repaired.' -ForegroundColor Yellow
    }
    else {
        Write-Host ("Canonical destination: line {0}, immediately after the install guard." -f $guard.Extent.EndLineNumber) -ForegroundColor Gray
    }

    $nonInteractive = '__StepperNonInteractive__'
    $hasDuplicates = $commands.Count -gt 1
    if (-not $hasDuplicates) {
        Write-Host ''
        if (-not $destinationUnavailable) {
            Write-Host '  [M] Move the existing call (Default)' -ForegroundColor Cyan
        }
        Write-Host '  [c] Continue for this invocation only' -ForegroundColor White
        Write-Host '  [q] Quit' -ForegroundColor White
        Write-Host ''
        Write-Host 'Choice? [' -NoNewline
        if (-not $destinationUnavailable) {
            Write-Host 'M' -NoNewline -ForegroundColor Cyan
            Write-Host '/c/q]: ' -NoNewline
        }
        else {
            Write-Host 'c/q]: ' -NoNewline
        }
        $choice = Read-StepperChoice -NonInteractiveDefault $nonInteractive

        if ($choice -eq $nonInteractive) {
            $exception = [System.InvalidOperationException]::new(
                "Non-interactive execution cannot relocate the Start-Stepper lifecycle call in '$ScriptPath'. Run interactively or move it immediately after the install guard inside the bootstrap Stepper-ignore region."
            )
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception,
                'LifecycleRemediationRequiresInteraction',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ScriptPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $choice = $choice.Trim().ToLowerInvariant()
        switch ($choice) {
            'c' {
                return New-StepperRemediationResult -Disposition Continue -HandledIssues $handledIssues `
                    -Message 'The misplaced lifecycle call was waived for this invocation only; validation remains unchanged.'
            }
            'q' {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'Lifecycle remediation was cancelled without changing the script.'
            }
            'm' {
                if ($destinationUnavailable) {
                    return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                        -Message 'The lifecycle call cannot be moved until the canonical bootstrap destination is available.'
                }
                $keeper = $commands[0]
            }
            '' {
                if ($destinationUnavailable) {
                    return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                        -Message 'The lifecycle call cannot be moved until the canonical bootstrap destination is available.'
                }
                $keeper = $commands[0]
            }
            default {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'The choice was not recognized; the script was not changed.'
            }
        }
    }
    else {
        Write-Host ''
        Write-Host 'Continue is unavailable because duplicate lifecycle calls can reinitialize execution state.' -ForegroundColor Yellow
        $canonicalCalls = @($commands | Where-Object {
            $pipeline = $_.Parent
            $isRoot = $pipeline -is [System.Management.Automation.Language.PipelineAst] -and $rootStatements -contains $pipeline
            $isInside = -not $destinationUnavailable -and
                $_.Extent.StartOffset -gt $guard.Extent.EndOffset -and
                $_.Extent.EndOffset -lt $bootstrapRegion.EndOffset
            $between = @($rootStatements | Where-Object {
                $_.Extent.StartOffset -ge $guard.Extent.EndOffset -and
                $_.Extent.EndOffset -le $pipeline.Extent.StartOffset -and
                $_ -ne $guard -and $_ -ne $pipeline
            })
            $isRoot -and $isInside -and $between.Count -eq 0
        })

        if ($destinationUnavailable) {
            Write-Host '  [q] Quit' -ForegroundColor White
            Write-Host ''
            Write-Host 'Choice? [q]: ' -NoNewline
            $choice = Read-StepperChoice -NonInteractiveDefault $nonInteractive
            if ($choice -eq $nonInteractive) {
                $exception = [System.InvalidOperationException]::new(
                    "Non-interactive execution cannot consolidate Start-Stepper lifecycle calls in '$ScriptPath'. Repair the bootstrap structure, then run interactively or edit the calls directly."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'LifecycleRemediationRequiresInteraction',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $ScriptPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                -Message 'Duplicate lifecycle calls cannot be consolidated until the canonical bootstrap destination is available.'
        }

        if ($canonicalCalls.Count -eq 1) {
            $keeper = $canonicalCalls[0]
            Write-Host ("  [R] Keep line {0} and remove every other lifecycle call (Default)" -f $keeper.Extent.StartLineNumber) -ForegroundColor Cyan
            Write-Host '  [q] Quit' -ForegroundColor White
            Write-Host ''
            Write-Host 'Choice? [' -NoNewline
            Write-Host 'R' -NoNewline -ForegroundColor Cyan
            Write-Host '/q]: ' -NoNewline
            $choice = Read-StepperChoice -NonInteractiveDefault $nonInteractive
            if ($choice -eq $nonInteractive) {
                $exception = [System.InvalidOperationException]::new(
                    "Non-interactive execution cannot remove duplicate Start-Stepper lifecycle calls in '$ScriptPath'. Run interactively or edit the calls directly."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'LifecycleRemediationRequiresInteraction',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $ScriptPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            $choice = $choice.Trim().ToLowerInvariant()
            if ($choice -eq 'q') {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'Duplicate lifecycle remediation was cancelled without changing the script.'
            }
            if ($choice -notin '', 'r') {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'The choice was not recognized; duplicate lifecycle calls were not changed.'
            }
        }
        else {
            for ($index = 0; $index -lt $commands.Count; $index++) {
                Write-Host ("  [{0}] Keep {1}" -f ($index + 1), $commands[$index].Extent.Text.Trim()) -ForegroundColor White
            }
            Write-Host '  [q] Quit' -ForegroundColor White
            Write-Host ''
            Write-Host ("Choice? [1-{0}/q]: " -f $commands.Count) -NoNewline
            $choice = Read-StepperChoice -NonInteractiveDefault $nonInteractive
            if ($choice -eq $nonInteractive) {
                $exception = [System.InvalidOperationException]::new(
                    "Non-interactive execution cannot choose among duplicate Start-Stepper lifecycle calls in '$ScriptPath'. Run interactively or edit the calls directly."
                )
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception,
                    'LifecycleRemediationRequiresInteraction',
                    [System.Management.Automation.ErrorCategory]::InvalidData,
                    $ScriptPath
                )
                $PSCmdlet.ThrowTerminatingError($errorRecord)
            }
            if ($choice.ToLowerInvariant() -eq 'q') {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'Duplicate lifecycle remediation was cancelled without changing the script.'
            }
            $selectedIndex = 0
            if (-not [int]::TryParse($choice, [ref]$selectedIndex) -or
                $selectedIndex -lt 1 -or $selectedIndex -gt $commands.Count) {
                return New-StepperRemediationResult -Disposition Quit -HandledIssues $handledIssues `
                    -Message 'No valid lifecycle call was selected; the script was not changed.'
            }
            $keeper = $commands[$selectedIndex - 1]
        }
    }

    $unsafeCommands = @($commands | Where-Object {
        $_.Parent -isnot [System.Management.Automation.Language.PipelineAst] -or
        $_.Parent.PipelineElements.Count -ne 1 -or
        $_.Parent.PipelineElements[0] -ne $_
    })
    if ($unsafeCommands.Count -gt 0) {
        $exception = [System.InvalidOperationException]::new(
            "Stepper cannot safely move a lifecycle call that shares a pipeline or statement in '$ScriptPath'. Put each Start-Stepper or Initialize-Stepper call on its own statement, then run the script again."
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'LifecycleRemediationRequiresManualEdit',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $ScriptPath
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $edits = [System.Collections.Generic.List[object]]::new()
    $keeperIsCanonical = $hasDuplicates -and @($canonicalCalls).Count -eq 1 -and $keeper -eq $canonicalCalls[0]

    foreach ($command in $commands) {
        if ($keeperIsCanonical -and $command -eq $keeper) { continue }
        $edits.Add([PSCustomObject]@{
            StartOffset = $command.Extent.StartOffset
            EndOffset   = $command.Extent.EndOffset
            Replacement = ''
        })
    }
    if (-not $keeperIsCanonical) {
        $edits.Add([PSCustomObject]@{
            StartOffset = $guard.Extent.EndOffset
            EndOffset   = $guard.Extent.EndOffset
            Replacement = "$newline$($keeper.Extent.Text)"
        })
    }

    $updatedContent = $content
    foreach ($edit in @($edits | Sort-Object StartOffset -Descending)) {
        $updatedContent = $updatedContent.Substring(0, $edit.StartOffset) +
            $edit.Replacement +
            $updatedContent.Substring($edit.EndOffset)
    }

    $transaction = Invoke-StepperRewriteTransaction -ScriptPath $ScriptPath -Content $updatedContent
    New-StepperRemediationResult -Disposition Rerun -HandledIssues $handledIssues -Changed $true `
        -BackupPath $transaction.BackupPath `
        -Message "Lifecycle calls were rewritten in one transaction. Re-run $scriptName."
}
