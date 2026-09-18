BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/New-StepperBackup.ps1"
    . "$ModulePath/Private/Get-StepperFindingCatalog.ps1"
    . "$ModulePath/Private/New-StepperIssue.ps1"
    . "$ModulePath/Private/Get-StepperScriptFindings.ps1"
    . "$ModulePath/Private/Read-StepperChoice.ps1"
    . "$ModulePath/Private/New-StepperRemediationResult.ps1"
    . "$ModulePath/Private/Invoke-StepperRewriteTransaction.ps1"
    . "$ModulePath/Private/Invoke-StepperLifecycleRemediation.ps1"
    . "$ModulePath/Private/Invoke-StepperUnmanagedCodeRemediation.ps1"
    . "$ModulePath/Private/Invoke-StepperMissingStopRemediation.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"

    function New-RemediationScript {
        param([string[]]$Lines)
        $path = Join-Path $TestDrive "$([guid]::NewGuid()).ps1"
        $Lines -join [Environment]::NewLine | Set-Content -LiteralPath $path -NoNewline
        return $path
    }

    function Set-RemediationResponses {
        param([string[]]$Responses)
        $script:__StepperTestResponses = [System.Collections.Generic.Queue[string]]::new()
        foreach ($response in $Responses) { $script:__StepperTestResponses.Enqueue($response) }
    }
}

Describe 'Stepper remediation handlers' -Tag 'Unit' {
    AfterEach {
        Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
    }

    Context 'Common result shape' {
        It 'Returns Continue, Quit, or Rerun fields consistently' {
            $path = New-RemediationScript @('Stop-Stepper')

            $result = Invoke-StepperMissingStopRemediation -ScriptPath $path -Issues @()

            $result.PSObject.Properties.Name | Should -Be @('Disposition', 'HandledIssues', 'Changed', 'BackupPath', 'Message')
            $result.Disposition | Should -Be 'Continue'
            $result.Changed | Should -BeFalse
        }
    }

    Context 'Lifecycle remediation' {
        It 'Moves one misplaced call while preserving spelling, options, and formatting' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Initialize-Stepper   -SkipRequirementsCheck'
                'New-Step { Write-Host "step" }'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'm'

            $result = Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues
            $content = Get-Content -LiteralPath $path -Raw

            $result.Disposition | Should -Be 'Rerun'
            $result.Changed | Should -BeTrue
            $result.BackupPath | Should -Exist
            $content | Should -Match '(?s)Install-Module Stepper -Force \}\r?\nInitialize-Stepper   -SkipRequirementsCheck\r?\n#endregion'
            ([regex]::Matches($content, 'Initialize-Stepper')).Count | Should -Be 1
            (Test-StepperScript -ScriptPath $path).Issues.Code | Should -Not -Contain 'StartOutsideBootstrapRegion'
        }

        It 'Refuses to move a lifecycle call that shares a pipeline' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Write-Output x | Start-Stepper'
                'New-Step { "step" }'
                'Stop-Stepper'
            )
            $before = Get-Content -LiteralPath $path -Raw
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'm'

            { Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues } |
                Should -Throw -ErrorId 'LifecycleRemediationRequiresManualEdit,Invoke-StepperLifecycleRemediation'
            (Get-Content -LiteralPath $path -Raw) | Should -BeExactly $before
        }

        It 'Allows a temporary Continue waiver for one misplaced call' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Start-Stepper'
                'New-Step { "step" }'
                'Stop-Stepper'
            )
            $before = Get-Content -LiteralPath $path -Raw
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'c'

            $result = Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues

            $result.Disposition | Should -Be 'Continue'
            $result.Changed | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -BeExactly $before
        }

        It 'Shows the default lifecycle choice uppercase and restores the Choice prompt' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Start-Stepper'
                'New-Step { "step" }'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'c'
            Mock Write-Host

            Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues | Out-Null

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [M] Move the existing call (Default)' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [c] Continue for this invocation only' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [q] Quit' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Choice? [' -and $NoNewline } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'M' -and $NoNewline -and $ForegroundColor -eq 'Cyan' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '/c/q]: ' -and $NoNewline } -Exactly 1 -Scope It
        }

        It 'Keeps the canonical call and removes all duplicates in one rewrite' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper -SkipRequirementsCheck'
                '#endregion Stepper ignore'
                'New-Step { "step" }'
                'Initialize-Stepper'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'r'
            Mock New-StepperBackup {
                $backup = "$Path.bak"
                Copy-Item -LiteralPath $Path -Destination $backup -Force
                $backup
            }

            $result = Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues
            $content = Get-Content -LiteralPath $path -Raw

            $result.Disposition | Should -Be 'Rerun'
            Should -Invoke New-StepperBackup -Times 1 -Exactly
            ([regex]::Matches($content, '(Start-Stepper|Initialize-Stepper)')).Count | Should -Be 1
            $content | Should -Match 'Start-Stepper -SkipRequirementsCheck'
            (Test-StepperScript -ScriptPath $path).Issues.Code | Should -Not -Contain 'DuplicateStartStepper'
        }

        It 'Does not guess a keeper when duplicate selection is invalid' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Start-Stepper -SkipRequirementsCheck'
                'New-Step { "step" }'
                'Initialize-Stepper'
                'Stop-Stepper'
            )
            $before = Get-Content -LiteralPath $path -Raw
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'invalid'

            $result = Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues

            $result.Disposition | Should -Be 'Quit'
            $result.Changed | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -BeExactly $before
        }

        It 'Fails safely without rewriting in a non-interactive run' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                '#endregion Stepper ignore'
                'Start-Stepper'
                'New-Step { "step" }'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Mock Read-StepperChoice { '__StepperNonInteractive__' }

            { Invoke-StepperLifecycleRemediation -ScriptPath $path -Issues $testResult.Issues } |
                Should -Throw -ErrorId 'LifecycleRemediationRequiresInteraction*'
        }
    }

    Context 'Unmanaged-code remediation' {
        It 'Wraps a complete source span including comments and blank lines' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'Write-Host "first"'
                '# keep this comment with the block'
                ''
                'Write-Host "second"'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'w'

            $result = Invoke-StepperUnmanagedCodeRemediation -ScriptPath $path -Issues $testResult.Issues
            $content = Get-Content -LiteralPath $path -Raw

            $result.Disposition | Should -Be 'Rerun'
            $content | Should -Match '(?s)New-Step \{\r?\n    Write-Host "first"\r?\n    # keep this comment with the block\r?\n\r?\n    Write-Host "second"\r?\n\}'
        }

        It 'Creates the first unnamed step in a zero-step script non-interactively' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'Write-Host "first step"'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Mock Read-StepperChoice { 'w' }

            $result = Invoke-StepperUnmanagedCodeRemediation -ScriptPath $path -Issues $testResult.Issues

            $result.Disposition | Should -Be 'Rerun'
            (Get-Content -LiteralPath $path -Raw) | Should -Match 'New-Step \{'
        }

        It 'Applies no earlier choices when a later block chooses Quit' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'Write-Host "first"'
                '#region Stepper ignore'
                '"boundary"'
                '#endregion Stepper ignore'
                'Write-Host "second"'
                'Stop-Stepper'
            )
            $before = Get-Content -LiteralPath $path -Raw
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses @('d', 'q')

            $result = Invoke-StepperUnmanagedCodeRemediation -ScriptPath $path -Issues $testResult.Issues

            $result.Disposition | Should -Be 'Quit'
            (Get-Content -LiteralPath $path -Raw) | Should -BeExactly $before
        }

        It 'Leaves unresolved NoSteps for the pipeline after Ignore-only decisions' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'Write-Host "still unmanaged"'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'i'

            $result = Invoke-StepperUnmanagedCodeRemediation -ScriptPath $path -Issues $testResult.Issues

            $result.Disposition | Should -Be 'Continue'
            $result.Changed | Should -BeFalse
            $result.HandledIssues.Code | Should -Not -Contain 'NoSteps'
        }

        It 'Shows the default unmanaged-code choice uppercase and restores the Choice prompt' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'Write-Host "still unmanaged"'
                'Stop-Stepper'
            )
            $testResult = Test-StepperScript -ScriptPath $path
            Set-RemediationResponses 'i'
            Mock Write-Host

            Invoke-StepperUnmanagedCodeRemediation -ScriptPath $path -Issues $testResult.Issues | Out-Null

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [W] Wrap in an unnamed New-Step (Default)' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [m] Mark ignored' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [d] Delete' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [i] Ignore for this invocation only' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [q] Quit without applying any decisions' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Choice? [' -and $NoNewline } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'W' -and $NoNewline -and $ForegroundColor -eq 'Cyan' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '/m/d/i/q]: ' -and $NoNewline } -Exactly 1 -Scope It
        }
    }

    Context 'Missing Stop remediation' {
        It 'Adds Stop-Stepper and removes stale state in one rewrite' {
            $path = New-RemediationScript @(
                '[CmdletBinding()]'
                'param()'
                'New-Step { "step" }'
            )
            $statePath = Get-StepperStatePath -ScriptPath $path
            Set-Content -LiteralPath $statePath -Value '{}'
            $issue = New-StepperIssue -Code MissingStopStepper
            Set-RemediationResponses 'a'
            Mock New-StepperBackup {
                $backup = "$Path.bak"
                Copy-Item -LiteralPath $Path -Destination $backup -Force
                $backup
            }

            $result = Invoke-StepperMissingStopRemediation -ScriptPath $path -Issues @($issue)

            $result.Disposition | Should -Be 'Rerun'
            Should -Invoke New-StepperBackup -Times 1 -Exactly
            $statePath | Should -Not -Exist
            (Get-Content -LiteralPath $path -Raw) | Should -Match 'Stop-Stepper'
        }

        It 'Continues without rewriting non-interactively' {
            $path = New-RemediationScript @('New-Step { "step" }')
            $before = Get-Content -LiteralPath $path -Raw
            $issue = New-StepperIssue -Code MissingStopStepper
            Mock Read-StepperChoice { 'c' }

            $result = Invoke-StepperMissingStopRemediation -ScriptPath $path -Issues @($issue) -WarningAction SilentlyContinue

            $result.Disposition | Should -Be 'Continue'
            $result.Changed | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -BeExactly $before
        }

        It 'Shows the default missing-Stop choice uppercase and restores the Choice prompt' {
            $path = New-RemediationScript @('New-Step { "step" }')
            $issue = New-StepperIssue -Code MissingStopStepper
            Mock Read-StepperChoice { 'c' }
            Mock Write-Host

            Invoke-StepperMissingStopRemediation -ScriptPath $path -Issues @($issue) -WarningAction SilentlyContinue | Out-Null

            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [A] Add Stop-Stepper (Default)' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [c] Continue for this invocation only' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '  [q] Quit' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Choice? [' -and $NoNewline } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'A' -and $NoNewline -and $ForegroundColor -eq 'Cyan' } -Exactly 1 -Scope It
            Should -Invoke Write-Host -ParameterFilter { $Object -eq '/c/q]: ' -and $NoNewline } -Exactly 1 -Scope It
        }
    }
}
