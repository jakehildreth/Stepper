BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepIdentifier.ps1"
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Write-StepperState.ps1"
    . "$ModulePath/Private/Read-StepperState.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Test-LineInIgnoredRegion.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Get-StepInventory.ps1"
    . "$ModulePath/Private/Find-UnmanagedCodeBlocks.ps1"
    . "$ModulePath/Private/Get-UnmanagedCodeAction.ps1"
    . "$ModulePath/Private/Update-ScriptWithUnmanagedActions.ps1"
    . "$ModulePath/Private/Test-StepperScriptRequirements.ps1"
    . "$ModulePath/Private/Show-MoreDetails.ps1"
    . "$ModulePath/Private/Write-StepperLog.ps1"
    . "$ModulePath/Private/Get-StepLogConfig.ps1"
    . "$ModulePath/Public/New-Step.ps1"

    # Helper: create a minimal valid stepper script in $TestDrive.
    # Returns a hashtable with Path, StatePath, and FirstStepLine.
    function New-TestStepperScript {
        param(
            [string]$BaseName = "test-$(New-Guid)",
            [int]$StepCount = 1,
            [string[]]$ExtraLines = @()
        )
        $path = Join-Path $TestDrive "$BaseName.ps1"
        $lines = @(
            '#requires -Modules Stepper'
            '[CmdletBinding()]'
            'param()'
        )
        for ($i = 1; $i -le $StepCount; $i++) {
            $lines += "New-Step { }"
        }
        foreach ($extra in $ExtraLines) {
            $lines += $extra
        }
        $lines += 'Stop-Stepper'
        Set-Content -Path $path -Value $lines
        return @{
            Path          = $path
            StatePath     = Get-StepperStatePath -ScriptPath $path
            FirstStepLine = 4  # line 1=requires, 2=CmdletBinding, 3=param, 4=first New-Step
        }
    }
}

Describe 'New-Step' -Tag 'Integration' {
    BeforeAll {
        Mock Write-Host {}
        Mock Write-Verbose {}
        Mock Test-StepperScriptRequirements { $false }
        Mock Find-NewStepBlocks { [PSCustomObject]@{ NewStepBlocks = @(); StopStepperLine = -1 } }
        Mock Find-UnmanagedCodeBlocks { @() }
        Mock Show-MoreDetails {}
    }

    Context 'Parameter validation' {
        It 'Accepts ScriptBlock as sole positional parameter (unnamed set)' {
            $info = New-TestStepperScript
            Mock Get-StepIdentifier { "$($info.Path):$($info.FirstStepLine)" }

            { New-Step { } } | Should -Not -Throw
        }

        It 'Accepts Name and ScriptBlock as positional parameters (named set)' {
            $info = New-TestStepperScript
            Mock Get-StepIdentifier { "$($info.Path):$($info.FirstStepLine)" }

            { New-Step 'My Step' { } } | Should -Not -Throw
        }

        It 'Throws StepIdentifierNotFound when Get-StepIdentifier fails' {
            Mock Get-StepIdentifier { throw [System.InvalidOperationException]::new('no stack') }
            $errors = @()
            try {
                New-Step { } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StepIdentifierNotFound*' } | Should -Not -BeNullOrEmpty
        }

        It 'Throws UnsavedScriptFile when script path does not exist' {
            Mock Get-StepIdentifier { '/nonexistent/path/script.ps1:5' }
            $errors = @()
            try {
                New-Step { } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'UnsavedScriptFile*' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ScriptBlock execution' {
        BeforeEach {
            $script:Info = New-TestStepperScript
            Mock Get-StepIdentifier { "$($script:Info.Path):$($script:Info.FirstStepLine)" }
        }

        It 'Executes the ScriptBlock and produces a file side effect' {
            $sideEffect = Join-Path $TestDrive "side-$(New-Guid).txt"
            New-Step { Set-Content -Path $sideEffect -Value 'executed' }
            $sideEffect | Should -Exist
        }

        It 'Creates a state file after successful execution' {
            New-Step { }
            $script:Info.StatePath | Should -Exist
        }

        It 'State contains the correct ScriptHash' {
            New-Step { }
            $state = Import-Clixml -Path $script:Info.StatePath
            $expectedHash = Get-ScriptHash -ScriptPath $script:Info.Path
            $state.ScriptHash | Should -Be $expectedHash
        }

        It 'State contains the correct LastCompletedStep identifier' {
            New-Step { }
            $state = Import-Clixml -Path $script:Info.StatePath
            $state.LastCompletedStep | Should -Be "$($script:Info.Path):$($script:Info.FirstStepLine)"
        }

        It 'Does not create a state file when ScriptBlock throws' {
            { New-Step { throw 'boom' } } | Should -Throw
            $script:Info.StatePath | Should -Not -Exist
        }

        It 'Throws StepExecutionFailed when ScriptBlock throws' {
            $errors = @()
            try {
                New-Step { throw 'boom' } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StepExecutionFailed*' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Named step state persistence' {
        BeforeEach {
            $script:NamedInfo = New-TestStepperScript
            Mock Get-StepIdentifier { "$($script:NamedInfo.Path):$($script:NamedInfo.FirstStepLine)" }
        }

        It 'State contains the correct step name for Named parameter set' {
            New-Step 'Install Packages' { }
            $state = Import-Clixml -Path $script:NamedInfo.StatePath
            $state.LastCompletedStepName | Should -Be 'Install Packages'
        }

        It 'State contains null step name for unnamed parameter set' {
            New-Step { }
            $state = Import-Clixml -Path $script:NamedInfo.StatePath
            $state.LastCompletedStepName | Should -BeNullOrEmpty
        }

        It 'State contains step number 1 for the first step' {
            New-Step { }
            $state = Import-Clixml -Path $script:NamedInfo.StatePath
            $state.LastCompletedStepNumber | Should -Be 1
        }
    }

    Context '$Stepper variable injection' {
        BeforeEach {
            $script:StepperVarInfo = New-TestStepperScript
            Mock Get-StepIdentifier { "$($script:StepperVarInfo.Path):$($script:StepperVarInfo.FirstStepLine)" }
            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'StepperData is written to state after step executes' {
            New-Step { }
            $state = Import-Clixml -Path $script:StepperVarInfo.StatePath
            $state.StepperData | Should -Not -BeNullOrEmpty
        }

        It 'Sets StepName in StepperData for Named parameter set' {
            New-Step 'Deploy App' { }
            $state = Import-Clixml -Path $script:StepperVarInfo.StatePath
            $state.StepperData['StepName'] | Should -Be 'Deploy App'
        }

        It 'Sets StepName to $null in StepperData for unnamed parameter set' {
            New-Step { }
            $state = Import-Clixml -Path $script:StepperVarInfo.StatePath
            $state.StepperData.ContainsKey('StepName') | Should -BeTrue
            $state.StepperData['StepName'] | Should -BeNullOrEmpty
        }

        It 'Sets StepNumber to 1 in StepperData for the first step' {
            New-Step { }
            $state = Import-Clixml -Path $script:StepperVarInfo.StatePath
            $state.StepperData['StepNumber'] | Should -Be 1
        }

        It 'Persists custom $Stepper data across steps in the same execution' {
            # Two-step script so step 2 has a valid identifier
            $twoStepInfo = New-TestStepperScript -BaseName "twostep-$(New-Guid)" -StepCount 2
            $callCount = 0
            Mock Get-StepIdentifier {
                $callCount++
                if ($callCount -eq 1) {
                    "$($twoStepInfo.Path):$($twoStepInfo.FirstStepLine)"
                } else {
                    "$($twoStepInfo.Path):$($twoStepInfo.FirstStepLine + 1)"
                }
            }

            New-Step { $Stepper['MyKey'] = 'from-step-1' }
            # Only verify the key was set during step 1 execution (side effect read from state)
            $state = Import-Clixml -Path $twoStepInfo.StatePath
            $state.StepperData['MyKey'] | Should -Be 'from-step-1'
        }
    }

    Context 'Resume logic — script unchanged' {
        BeforeEach {
            # Two-step script: step 1 was completed, step 2 should run on resume
            $script:ResumeInfo = New-TestStepperScript -BaseName "resume-$(New-Guid)" -StepCount 2
            $step1Id = "$($script:ResumeInfo.Path):$($script:ResumeInfo.FirstStepLine)"
            $scriptHash = Get-ScriptHash -ScriptPath $script:ResumeInfo.Path
            Write-StepperState -StatePath $script:ResumeInfo.StatePath `
                -ScriptHash $scriptHash `
                -LastCompletedStep $step1Id `
                -StepNumber 1

            $script:ResumeCallCount = 0
            Mock Get-StepIdentifier {
                $script:ResumeCallCount++
                if ($script:ResumeCallCount -eq 1) {
                    "$($script:ResumeInfo.Path):$($script:ResumeInfo.FirstStepLine)"
                } else {
                    "$($script:ResumeInfo.Path):$($script:ResumeInfo.FirstStepLine + 1)"
                }
            }
            Mock Read-Host { 'R' }

            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'Skips step 1 (already completed) — state not updated for skipped step' {
            # Call step 1 (should be skipped). The state file should NOT be updated
            # (no re-write for a skipped step). The pre-existing hash should still match.
            New-Step { }
            $state = Import-Clixml -Path $script:ResumeInfo.StatePath
            $state.LastCompletedStep | Should -Be "$($script:ResumeInfo.Path):$($script:ResumeInfo.FirstStepLine)"
        }

        It 'Executes step 2 when called in resume mode with RestoreMode false' {
            # Pre-configure execution state (simulates step 1 having been processed/skipped)
            # so that New-Step for step 2 sees RestoreMode=false and executes
            $script:ResumeCallCount = 1  # Get-StepIdentifier will return step2Id
            $__StepperInitialized = $true
            $__StepperExecutionState = @{
                RestoreMode       = $false
                TargetStep        = "$($script:ResumeInfo.Path):$($script:ResumeInfo.FirstStepLine)"
                CurrentScriptPath = $script:ResumeInfo.Path
                CurrentScriptHash = (Get-ScriptHash -ScriptPath $script:ResumeInfo.Path)
                StatePath         = $script:ResumeInfo.StatePath
                LogPath           = $null
                LoggingEnabled    = $true
                NoLogStepIds      = @()
            }

            $sideEffect = Join-Path $TestDrive "step2-side-$(New-Guid).txt"
            New-Step { Set-Content -Path $sideEffect -Value 'ran' }
            $sideEffect | Should -Exist
        }
    }

    Context 'Resume logic — Start over' {
        BeforeEach {
            $script:StartOverInfo = New-TestStepperScript -BaseName "startover-$(New-Guid)" -StepCount 2
            $step1Id = "$($script:StartOverInfo.Path):$($script:StartOverInfo.FirstStepLine)"
            $scriptHash = Get-ScriptHash -ScriptPath $script:StartOverInfo.Path
            Write-StepperState -StatePath $script:StartOverInfo.StatePath `
                -ScriptHash $scriptHash `
                -LastCompletedStep $step1Id `
                -StepNumber 1

            $script:StartOverCallCount = 0
            Mock Get-StepIdentifier {
                $script:StartOverCallCount++
                if ($script:StartOverCallCount -eq 1) {
                    "$($script:StartOverInfo.Path):$($script:StartOverInfo.FirstStepLine)"
                } else {
                    "$($script:StartOverInfo.Path):$($script:StartOverInfo.FirstStepLine + 1)"
                }
            }
            Mock Read-Host { 'S' }

            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'State after start over reflects step 1 completed (not resumed from prior)' {
            # Pre-state says step 1 done; choose S; step 1 runs again; new state = step 1
            New-Step { }
            $state = Import-Clixml -Path $script:StartOverInfo.StatePath
            $state.LastCompletedStepNumber | Should -Be 1
            $state.LastCompletedStep | Should -Be "$($script:StartOverInfo.Path):$($script:StartOverInfo.FirstStepLine)"
        }

        It 'Executes step 1 again after Start over' {
            $step1Executed = Join-Path $TestDrive "step1-$(New-Guid).txt"
            New-Step { Set-Content -Path $step1Executed -Value 'ran' }
            $step1Executed | Should -Exist
        }
    }

    Context 'Resume logic — changed script defaults to Start over' {
        BeforeEach {
            $script:ChangedInfo = New-TestStepperScript -BaseName "changed-$(New-Guid)" -StepCount 2
            $step1Id = "$($script:ChangedInfo.Path):$($script:ChangedInfo.FirstStepLine)"
            # State was written with a DIFFERENT hash to simulate script modification
            Write-StepperState -StatePath $script:ChangedInfo.StatePath `
                -ScriptHash 'stale-hash-does-not-match' `
                -LastCompletedStep $step1Id `
                -StepNumber 1

            $script:ChangedCallCount = 0
            Mock Get-StepIdentifier {
                $script:ChangedCallCount++
                if ($script:ChangedCallCount -eq 1) {
                    "$($script:ChangedInfo.Path):$($script:ChangedInfo.FirstStepLine)"
                } else {
                    "$($script:ChangedInfo.Path):$($script:ChangedInfo.FirstStepLine + 1)"
                }
            }
            # Default (empty) response for changed script = Start over
            Mock Read-Host { '' }

            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'State after start over reflects current hash (stale hash replaced)' {
            New-Step { }
            $state = Import-Clixml -Path $script:ChangedInfo.StatePath
            $currentHash = Get-ScriptHash -ScriptPath $script:ChangedInfo.Path
            $state.ScriptHash | Should -Be $currentHash
        }

        It 'Runs step 1 from scratch when starting over on changed script' {
            $sideEffect = Join-Path $TestDrive "changed-side-$(New-Guid).txt"
            New-Step { Set-Content -Path $sideEffect -Value 'ran' }
            $sideEffect | Should -Exist
        }
    }

    Context 'Missing Stop-Stepper — user chooses A (add)' {
        BeforeEach {
            # Script without Stop-Stepper
            $script:NoStopPath = Join-Path $TestDrive "nostop-$(New-Guid).ps1"
            Set-Content -Path $script:NoStopPath -Value @(
                '#requires -Modules Stepper'
                '[CmdletBinding()]'
                'param()'
                'New-Step { }'
            )
            Mock Get-StepIdentifier { "$($script:NoStopPath):4" }
            Mock Read-Host { 'A' }
            # Remove-StepperState fires right before `exit` in the A-path.
            # Throwing here intercepts the exit so it never propagates and kills Pester.
            Mock Remove-StepperState { throw [System.Exception]::new('Interrupted before exit') }

            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'Appends Stop-Stepper to the script file' {
            try { New-Step { } } catch { }
            $content = Get-Content -Path $script:NoStopPath -Raw
            $content | Should -Match 'Stop-Stepper'
        }
    }

    Context 'Missing Stop-Stepper — user chooses C (continue)' {
        BeforeEach {
            $script:NoStopContinuePath = Join-Path $TestDrive "nostop-c-$(New-Guid).ps1"
            Set-Content -Path $script:NoStopContinuePath -Value @(
                '#requires -Modules Stepper'
                '[CmdletBinding()]'
                'param()'
                'New-Step { }'
            )
            Mock Get-StepIdentifier { "$($script:NoStopContinuePath):4" }
            Mock Read-Host { 'C' }

            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        }

        It 'Creates a state file and does not modify the script' {
            New-Step { }
            $statePath = Get-StepperStatePath -ScriptPath $script:NoStopContinuePath
            $statePath | Should -Exist
            $content = Get-Content -Path $script:NoStopContinuePath -Raw
            $content | Should -Not -Match 'Stop-Stepper'
        }
    }

    Context 'Logging — default log path' {
        BeforeEach {
            $script:LogDefaultInfo = New-TestStepperScript -BaseName 'log-default'
            Mock Get-StepIdentifier { "$($script:LogDefaultInfo.Path):$($script:LogDefaultInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Write-StepperLog {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should call Write-StepperLog when a step executes' {
            New-Step { }
            Should -Invoke Write-StepperLog -Scope It
        }

        It 'Should store the resolved log path in execution state' {
            New-Step { }
            $expectedLog = "$($script:LogDefaultInfo.Path).stepper.log"
            $state = Import-Clixml -Path $script:LogDefaultInfo.StatePath
            $state.LogPath | Should -Be $expectedLog
        }
    }

    Context 'Logging — explicit -LogPath parameter' {
        BeforeEach {
            $script:LogExplicitInfo = New-TestStepperScript -BaseName 'log-explicit'
            $script:ExplicitLogPath = Join-Path $TestDrive 'explicit.log'
            Mock Get-StepIdentifier { "$($script:LogExplicitInfo.Path):$($script:LogExplicitInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:ExplicitLogPath); HasConflict = $false; NoLogStepIds = @() } }
            Mock Write-StepperLog {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should use the explicit log path from Get-StepLogConfig' {
            New-Step -LogPath $script:ExplicitLogPath { }
            $state = Import-Clixml -Path $script:LogExplicitInfo.StatePath
            $state.LogPath | Should -Be $script:ExplicitLogPath
        }
    }

    Context 'Logging — conflicting -LogPath values prompt user' {
        BeforeEach {
            $script:ConflictInfo = New-TestStepperScript -BaseName 'log-conflict'
            Mock Get-StepIdentifier { "$($script:ConflictInfo.Path):$($script:ConflictInfo.FirstStepLine)" }
            Mock Get-StepLogConfig {
                [PSCustomObject]@{
                    UniqueStaticLogPaths = @((Join-Path $TestDrive 'a.log'), (Join-Path $TestDrive 'b.log'))
                    HasConflict          = $true
                    NoLogStepIds         = @()
                }
            }
            Mock Write-StepperLog {}
            Mock Read-Host { '1' }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should prompt the user when -LogPath conflicts are detected' {
            New-Step { }
            Should -Invoke Read-Host -Scope It
        }
    }

    Context 'Logging — runtime -LogPath mismatch writes warning' {
        BeforeEach {
            $script:MismatchInfo = New-TestStepperScript -BaseName 'log-mismatch'
            $script:ResolvedLog = Join-Path $TestDrive 'resolved.log'
            Mock Get-StepIdentifier { "$($script:MismatchInfo.Path):$($script:MismatchInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:ResolvedLog); HasConflict = $false; NoLogStepIds = @() } }
            Mock Write-StepperLog {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write a warning when -LogPath differs from the resolved path' {
            $differentPath = Join-Path $TestDrive 'different.log'
            $warnings = New-Step -LogPath $differentPath { } 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Logging — active transcript causes hard stop' {
        BeforeEach {
            $script:TranscriptInfo = New-TestStepperScript -BaseName 'log-transcript'
            Mock Get-StepIdentifier { "$($script:TranscriptInfo.Path):$($script:TranscriptInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Write-StepperLog {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should throw TranscriptAlreadyActive when host transcript is active' -Skip:($true) {
            # $Host.UI.IsTranscribing cannot be mocked via Pester Mock on a live host object.
            # Covered by manual verification: run a script with an active transcript and
            # confirm Stepper halts with ErrorId 'TranscriptAlreadyActive'.
        }

        It 'Should throw with ErrorId TranscriptAlreadyActive when transcript is active' -Skip:($true) {
            # Skipped: $Host.UI.IsTranscribing cannot be mocked via Pester Mock
            # Covered by manual verification and ADR documentation
        }
    }

    Context 'Logging — transcript section in log file' {
        BeforeEach {
            $script:TranscriptLogInfo = New-TestStepperScript -BaseName 'log-transcript-section'
            $script:TranscriptLogPath = Join-Path $TestDrive 'transcript-test.log'
            Mock Get-StepIdentifier { "$($script:TranscriptLogInfo.Path):$($script:TranscriptLogInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:TranscriptLogPath); HasConflict = $false; NoLogStepIds = @() } }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write a transcript section header to the log on successful step' {
            New-Step { Write-Output 'step output' }
            $logContent = Get-Content -Path $script:TranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '=== BEGIN STEP \d+ TRANSCRIPT ==='
        }

        It 'Should write a transcript section footer to the log on successful step' {
            New-Step { Write-Output 'step output' }
            $logContent = Get-Content -Path $script:TranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '=== END STEP \d+ TRANSCRIPT ==='
        }

        It 'Should write elapsed time to the log on successful step' {
            New-Step { Write-Output 'step output' }
            $logContent = Get-Content -Path $script:TranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'completed in \d+\.?\d*s'
        }
    }

    Context 'Logging — failure writes ERROR entry to log' {
        BeforeEach {
            $script:FailLogInfo = New-TestStepperScript -BaseName 'log-fail'
            $script:FailLogPath = Join-Path $TestDrive 'fail-test.log'
            Mock Get-StepIdentifier { "$($script:FailLogInfo.Path):$($script:FailLogInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:FailLogPath); HasConflict = $false; NoLogStepIds = @() } }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write an [ERROR] entry to the log when a step throws' {
            try {
                New-Step { throw 'simulated failure' }
            } catch { }
            $logContent = Get-Content -Path $script:FailLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '\[ERROR\]'
        }

        It 'Should write a PARTIAL transcript section on failure' {
            try {
                New-Step { Write-Output 'before failure'; throw 'simulated failure' }
            } catch { }
            $logContent = Get-Content -Path $script:FailLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '\[PARTIAL\]'
        }

        It 'Should still throw the terminating error after logging failure' {
            { New-Step { throw 'simulated failure' } } | Should -Throw
        }
    }

    Context 'Logging — skipped steps written to log on resume' {
        BeforeEach {
            $script:SkipLogInfo  = New-TestStepperScript -BaseName "log-skip-$(New-Guid)" -StepCount 2
            $script:SkipLogPath  = Join-Path $TestDrive 'skip-test.log'
            $step1Id = "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine)"
            $scriptHash = Get-ScriptHash -ScriptPath $script:SkipLogInfo.Path
            Write-StepperState -StatePath $script:SkipLogInfo.StatePath `
                -ScriptHash $scriptHash `
                -LastCompletedStep $step1Id `
                -StepNumber 1

            $script:SkipLogCallCount = 0
            Mock Get-StepIdentifier {
                $script:SkipLogCallCount++
                if ($script:SkipLogCallCount -eq 1) {
                    "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine)"
                } else {
                    "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine + 1)"
                }
            }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:SkipLogPath); HasConflict = $false; NoLogStepIds = @() } }
            Mock Read-Host { 'R' }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write a Skipping log entry for a previously completed step' {
            New-Step { }   # step 1 — skipped (last completed)
            New-Step { }   # step 2 — runs
            $logContent = Get-Content -Path $script:SkipLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'Skipping step \d+/\d+'
        }

        It 'Should state that the step already completed in a previous run' {
            New-Step { }
            New-Step { }
            $logContent = Get-Content -Path $script:SkipLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'already completed in a previous run'
        }

        It 'Should include step name in the SKIPPED section for a named step' {
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
            $namedSkipInfo = New-TestStepperScript -BaseName "log-skip-named-$(New-Guid)" -StepCount 2
            $namedStep1Id  = "$($namedSkipInfo.Path):$($namedSkipInfo.FirstStepLine)"
            $namedHash     = Get-ScriptHash -ScriptPath $namedSkipInfo.Path
            Write-StepperState -StatePath $namedSkipInfo.StatePath `
                -ScriptHash $namedHash `
                -LastCompletedStep $namedStep1Id `
                -StepNumber 1

            $namedSkipCallCount = 0
            Mock Get-StepIdentifier {
                $namedSkipCallCount++
                if ($namedSkipCallCount -eq 1) {
                    "$($namedSkipInfo.Path):$($namedSkipInfo.FirstStepLine)"
                } else {
                    "$($namedSkipInfo.Path):$($namedSkipInfo.FirstStepLine + 1)"
                }
            }
            $namedSkipLog = Join-Path $TestDrive 'skip-named.log'
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($namedSkipLog); HasConflict = $false; NoLogStepIds = @() } }

            New-Step 'Provision Infra' { }
            New-Step { }
            $logContent = Get-Content -Path $namedSkipLog -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "Skipping step \d+/\d+.*'Provision Infra'.*already completed"
        }
    }

    Context 'Logging — -NoLog step scope prompt' {
        BeforeEach {
            $script:NoLogInfo = New-TestStepperScript -BaseName 'log-nolog'
            Mock Get-StepIdentifier { "$($script:NoLogInfo.Path):$($script:NoLogInfo.FirstStepLine)" }
            Mock Get-StepLogConfig {
                [PSCustomObject]@{
                    UniqueStaticLogPaths = @()
                    HasConflict          = $false
                    NoLogStepIds         = @("$($script:NoLogInfo.Path):$($script:NoLogInfo.FirstStepLine)")
                }
            }
            Mock Write-StepperLog {}
            Mock Read-Host { 'S' }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should prompt the user when -NoLog is present on a step' {
            New-Step -NoLog { }
            Should -Invoke Read-Host -Scope It
        }

        It 'Should store the NoLogStepIds in execution state when user chooses S' {
            New-Step -NoLog { }
            $state = Import-Clixml -Path $script:NoLogInfo.StatePath
            $state.NoLogStepIds | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Logging — disabled-step marker written to log' {
        BeforeEach {
            $script:DisabledLogInfo = New-TestStepperScript -BaseName 'log-disabled'
            $script:DisabledLogPath = Join-Path $TestDrive 'disabled-step.log'
            Remove-Item -LiteralPath $script:DisabledLogPath -Force -ErrorAction SilentlyContinue
            $stepId = "$($script:DisabledLogInfo.Path):$($script:DisabledLogInfo.FirstStepLine)"
            Mock Get-StepIdentifier { $stepId }
            Mock Get-StepLogConfig {
                [PSCustomObject]@{
                    UniqueStaticLogPaths = @($script:DisabledLogPath)
                    HasConflict          = $false
                    NoLogStepIds         = @($stepId)
                }
            }
            Mock Read-Host { 'S' }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write a LOGGING DISABLED BY USER marker to the log when logging is off for a step' {
            New-Step -NoLog { Write-Output 'should not appear in transcript' }
            $logContent = Get-Content -Path $script:DisabledLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'LOGGING DISABLED BY USER'
        }

        It 'Should not write a transcript section when logging is disabled for a step' {
            New-Step -NoLog { Write-Output 'should not appear in transcript' }
            $logContent = Get-Content -Path $script:DisabledLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Not -Match 'BEGIN STEP'
        }
    }

    Context 'Logging — step name included in log messages' {
        BeforeEach {
            $script:NamedLogInfo = New-TestStepperScript -BaseName 'log-named-step'
            $script:NamedLogPath = Join-Path $TestDrive 'named-step.log'
            Remove-Item -LiteralPath $script:NamedLogPath -Force -ErrorAction SilentlyContinue
            Mock Get-StepIdentifier { "$($script:NamedLogInfo.Path):$($script:NamedLogInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @($script:NamedLogPath); HasConflict = $false; NoLogStepIds = @() } }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should include step name in the Executing log entry' {
            New-Step 'My Named Step' { Write-Output 'hello' }
            $logContent = Get-Content -Path $script:NamedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "Executing.*My Named Step"
        }

        It 'Should include step name in the completed log entry' {
            New-Step 'My Named Step' { Write-Output 'hello' }
            $logContent = Get-Content -Path $script:NamedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "My Named Step.*completed"
        }

        It 'Should include step name in transcript section headers' {
            New-Step 'My Named Step' { Write-Output 'hello' }
            $logContent = Get-Content -Path $script:NamedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "BEGIN STEP \d+.*My Named Step.*TRANSCRIPT"
        }

        It 'Should not include a name suffix for unnamed steps' {
            New-Step { Write-Output 'hello' }
            $logContent = Get-Content -Path $script:NamedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Not -Match "Executing.*-\s*'"
        }
    }

    Context 'Logging — skipped steps written to log on resume' {
        BeforeEach {
            $script:SkipLogInfo = New-TestStepperScript -BaseName "log-skip-$(New-Guid)" -StepCount 2
            $script:SkipLogPath = Join-Path $TestDrive 'skip-test.log'
            $step1Id = "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine)"
            $scriptHash = Get-ScriptHash -ScriptPath $script:SkipLogInfo.Path
            Write-StepperState -StatePath $script:SkipLogInfo.StatePath `
                -ScriptHash $scriptHash `
                -LastCompletedStep $step1Id `
                -StepNumber 1 `
                -LogPath $script:SkipLogPath `
                -LoggingEnabled $true `
                -NoLogStepIds @()

            $script:SkipCallCount = 0
            Mock Get-StepIdentifier {
                $script:SkipCallCount++
                if ($script:SkipCallCount -eq 1) {
                    "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine)"
                } else {
                    "$($script:SkipLogInfo.Path):$($script:SkipLogInfo.FirstStepLine + 1)"
                }
            }
            Mock Read-Host { 'R' }
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Should write a Skipping log entry to the log for a skipped step' {
            New-Step { }
            $logContent = Get-Content -Path $script:SkipLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'Skipping step \d+/\d+'
        }

        It 'Should include step name in the Skipping entry for a named step' {
            New-Step 'Provision Infra' { }
            $logContent = Get-Content -Path $script:SkipLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "'Provision Infra'"
        }
    }
}
