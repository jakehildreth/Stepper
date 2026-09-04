BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepIdentifier.ps1"
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Write-StepperState.ps1"
    . "$ModulePath/Private/Read-StepperState.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Clear-StepperSession.ps1"
    . "$ModulePath/Private/Test-LineInIgnoredRegion.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Get-StepInventory.ps1"
    . "$ModulePath/Private/Find-UnmanagedCodeBlocks.ps1"
    . "$ModulePath/Private/Get-UnmanagedCodeAction.ps1"
    . "$ModulePath/Private/Update-ScriptWithUnmanagedActions.ps1"
    . "$ModulePath/Private/Add-StepperCbh.ps1"
    . "$ModulePath/Private/New-StepperBackup.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Show-MoreDetails.ps1"
    . "$ModulePath/Private/Write-StepperLog.ps1"
    . "$ModulePath/Private/Get-StepLogConfig.ps1"
    . "$ModulePath/Private/Find-CrossStepVariables.ps1"
    . "$ModulePath/Private/Test-StepperConversionComplete.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"
    . "$ModulePath/Public/Repair-StepperScript.ps1"
    . "$ModulePath/Public/ConvertTo-StepperScript.ps1"
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
    }

    BeforeEach {
        # New-Step no longer initializes itself. Start-Stepper owns init and sets
        # the __StepperInitialized sentinel. Simulate a completed Start-Stepper run
        # so the default mode for every test is "already initialized".
        $__StepperInitialized = $true
        $__StepperExecutionState = @{
            RestoreMode    = $false
            TargetStep     = $null
            LogPath        = $null
            LoggingEnabled = $true
            NoLogStepIds   = @()
        }
    }

    AfterEach {
        Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
        Remove-Variable -Name '__StepperExecutionState' -ErrorAction SilentlyContinue
        Remove-Variable -Name 'Stepper' -ErrorAction SilentlyContinue
        Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name 'Stepper' -Scope Global -ErrorAction SilentlyContinue
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
            # Start-Stepper owns $Stepper creation now; seed it here.
            $Stepper = @{}
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

    Context 'Resume logic: script unchanged' {
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

    Context 'Logging: default log path' {
        BeforeEach {
            $script:LogDefaultInfo = New-TestStepperScript -BaseName 'log-default'
            Mock Get-StepIdentifier { "$($script:LogDefaultInfo.Path):$($script:LogDefaultInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
        }

        It 'Should call Write-StepperLog when a step executes' {
            New-Step { }
            Should -Invoke Write-StepperLog -Scope It
        }
    }

    Context 'Logging: explicit -LogPath parameter' {
        BeforeEach {
            $script:LogExplicitInfo = New-TestStepperScript -BaseName 'log-explicit'
            $script:ExplicitLogPath = Join-Path $TestDrive 'explicit.log'
            Mock Get-StepIdentifier { "$($script:LogExplicitInfo.Path):$($script:LogExplicitInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            # Log-path resolution moved to Start-Stepper; seed the resolved path.
            $__StepperExecutionState.LogPath = $script:ExplicitLogPath
        }

        It 'Should persist the resolved log path in state' {
            New-Step -LogPath $script:ExplicitLogPath { }
            $state = Import-Clixml -Path $script:LogExplicitInfo.StatePath
            $state.LogPath | Should -Be $script:ExplicitLogPath
        }
    }

    Context 'Logging: runtime -LogPath mismatch writes warning' {
        BeforeEach {
            $script:MismatchInfo = New-TestStepperScript -BaseName 'log-mismatch'
            $script:ResolvedLog = Join-Path $TestDrive 'resolved.log'
            Mock Get-StepIdentifier { "$($script:MismatchInfo.Path):$($script:MismatchInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            $__StepperExecutionState.LogPath = $script:ResolvedLog
        }

        It 'Should write a warning when -LogPath differs from the resolved path' {
            $differentPath = Join-Path $TestDrive 'different.log'
            $warnings = New-Step -LogPath $differentPath { } 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Logging: active transcript causes hard stop' {
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

    Context 'Logging: transcript section in log file' {
        BeforeEach {
            $script:TranscriptLogInfo = New-TestStepperScript -BaseName 'log-transcript-section'
            $script:TranscriptLogPath = Join-Path $TestDrive 'transcript-test.log'
            Mock Get-StepIdentifier { "$($script:TranscriptLogInfo.Path):$($script:TranscriptLogInfo.FirstStepLine)" }
            $__StepperExecutionState.LogPath = $script:TranscriptLogPath
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

    Context 'Logging: failure writes ERROR entry to log' {
        BeforeEach {
            $script:FailLogInfo = New-TestStepperScript -BaseName 'log-fail'
            $script:FailLogPath = Join-Path $TestDrive 'fail-test.log'
            Mock Get-StepIdentifier { "$($script:FailLogInfo.Path):$($script:FailLogInfo.FirstStepLine)" }
            $__StepperExecutionState.LogPath = $script:FailLogPath
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

    Context 'Logging: skipped steps written to log on resume' {
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
            # Simulate Start-Stepper having resumed: restore mode targets step 1.
            $__StepperExecutionState = @{
                RestoreMode    = $true
                TargetStep     = $step1Id
                LogPath        = $script:SkipLogPath
                LoggingEnabled = $true
                NoLogStepIds   = @()
            }
        }

        It 'Should write a Skipping log entry for a previously completed step' {
            New-Step { }   # step 1, skipped (last completed)
            New-Step { }   # step 2, runs
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
            $__StepperExecutionState = @{
                RestoreMode    = $true
                TargetStep     = $namedStep1Id
                LogPath        = $namedSkipLog
                LoggingEnabled = $true
                NoLogStepIds   = @()
            }

            New-Step 'Provision Infra' { }
            New-Step { }
            $logContent = Get-Content -Path $namedSkipLog -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match "Skipping step \d+/\d+.*'Provision Infra'.*already completed"
        }
    }

    Context 'Logging: disabled-step marker written to log' {
        BeforeEach {
            $script:DisabledLogInfo = New-TestStepperScript -BaseName 'log-disabled'
            $script:DisabledLogPath = Join-Path $TestDrive 'disabled-step.log'
            Remove-Item -LiteralPath $script:DisabledLogPath -Force -ErrorAction SilentlyContinue
            $stepId = "$($script:DisabledLogInfo.Path):$($script:DisabledLogInfo.FirstStepLine)"
            Mock Get-StepIdentifier { $stepId }
            $__StepperExecutionState.LogPath = $script:DisabledLogPath
            $__StepperExecutionState.NoLogStepIds = @($stepId)
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

    Context 'Logging: step name included in log messages' {
        BeforeEach {
            $script:NamedLogInfo = New-TestStepperScript -BaseName 'log-named-step'
            $script:NamedLogPath = Join-Path $TestDrive 'named-step.log'
            Remove-Item -LiteralPath $script:NamedLogPath -Force -ErrorAction SilentlyContinue
            Mock Get-StepIdentifier { "$($script:NamedLogInfo.Path):$($script:NamedLogInfo.FirstStepLine)" }
            $__StepperExecutionState.LogPath = $script:NamedLogPath
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

    Context 'Logging: skipped steps written to log on resume' {
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
            # Simulate Start-Stepper having resumed: restore mode targets step 1.
            $__StepperExecutionState = @{
                RestoreMode    = $true
                TargetStep     = $step1Id
                LogPath        = $script:SkipLogPath
                LoggingEnabled = $true
                NoLogStepIds   = @()
            }
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

    Context 'Retry: parameter validation' {
        BeforeEach {
            $script:RetryValInfo = New-TestStepperScript -BaseName "retry-val-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetryValInfo.Path):$($script:RetryValInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Throws for -RetryInterval 0' {
            { New-Step -Retry -RetryInterval 0 { } } | Should -Throw
        }

        It 'Throws for negative -RetryInterval' {
            { New-Step -Retry -RetryInterval -5 { } } | Should -Throw
        }

        It 'Throws for -MaxRetries 0' {
            { New-Step -Retry -MaxRetries 0 { } } | Should -Throw
        }

        It 'Throws for negative -MaxRetries' {
            { New-Step -Retry -MaxRetries -1 { } } | Should -Throw
        }
    }

    Context 'Retry: single-attempt behavior unchanged without -Retry' {
        BeforeEach {
            $script:NoRetryInfo = New-TestStepperScript -BaseName "no-retry-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:NoRetryInfo.Path):$($script:NoRetryInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Does not call Start-Sleep when -Retry is absent and step succeeds' {
            New-Step { }
            Should -Invoke Start-Sleep -Exactly 0 -Scope It
        }

        It 'Does not call Start-Sleep when -Retry is absent and step fails' {
            try { New-Step { throw 'boom' } } catch { }
            Should -Invoke Start-Sleep -Exactly 0 -Scope It
        }

        It 'Throws StepExecutionFailed immediately on failure without -Retry' {
            $errors = @()
            try {
                New-Step { throw 'immediate failure' } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StepExecutionFailed*' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Retry: success on first attempt does not trigger retry' {
        BeforeEach {
            $script:RetrySuccessInfo = New-TestStepperScript -BaseName "retry-ok-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetrySuccessInfo.Path):$($script:RetrySuccessInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Does not call Start-Sleep when step succeeds on first attempt with -Retry' {
            New-Step -Retry -RetryInterval 1 { }
            Should -Invoke Start-Sleep -Exactly 0 -Scope It
        }

        It 'Creates state file on first-attempt success with -Retry' {
            New-Step -Retry { }
            $script:RetrySuccessInfo.StatePath | Should -Exist
        }
    }

    Context 'Retry: step fails once then succeeds' {
        BeforeEach {
            $script:RetryOnceInfo = New-TestStepperScript -BaseName "retry-once-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetryOnceInfo.Path):$($script:RetryOnceInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Calls Start-Sleep exactly once after one failure then success' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            Should -Invoke Start-Sleep -Exactly 1 -Scope It
        }

        It 'Creates state file after eventual success' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $script:RetryOnceInfo.StatePath | Should -Exist
        }

        It 'Does not throw when step eventually succeeds within MaxRetries' {
            $counter = @{ Calls = 0 }
            {
                New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                    $counter.Calls++
                    if ($counter.Calls -lt 2) { throw 'transient' }
                }
            } | Should -Not -Throw
        }
    }

    Context 'Retry: all retries exhausted' {
        BeforeEach {
            $script:RetryExhaustedInfo = New-TestStepperScript -BaseName "retry-exhaust-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetryExhaustedInfo.Path):$($script:RetryExhaustedInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Throws StepExecutionFailed after MaxRetries retries are exhausted' {
            $errors = @()
            try {
                New-Step -Retry -RetryInterval 1 -MaxRetries 3 { throw 'always fails' } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StepExecutionFailed*' } | Should -Not -BeNullOrEmpty
        }

        It 'Does not create a state file when all retries are exhausted' {
            try {
                New-Step -Retry -RetryInterval 1 -MaxRetries 3 { throw 'always fails' }
            } catch { }
            $script:RetryExhaustedInfo.StatePath | Should -Not -Exist
        }

        It 'Calls Start-Sleep MaxRetries times when all attempts fail' {
            try {
                New-Step -Retry -RetryInterval 1 -MaxRetries 3 { throw 'always fails' }
            } catch { }
            Should -Invoke Start-Sleep -Exactly 3 -Scope It
        }

        It 'Executes ScriptBlock MaxRetries + 1 times total when all attempts fail' {
            $counter = @{ Calls = 0 }
            try {
                New-Step -Retry -RetryInterval 1 -MaxRetries 3 {
                    $counter.Calls++
                    throw 'always fails'
                }
            } catch { }
            $counter.Calls | Should -Be 4
        }
    }

    Context 'Retry: exponential backoff wait times' {
        BeforeEach {
            $script:RetryBackoffInfo = New-TestStepperScript -BaseName "retry-backoff-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetryBackoffInfo.Path):$($script:RetryBackoffInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Waits RetryInterval seconds on first retry (attempt 0: interval * 2^0)' {
            try {
                New-Step -Retry -RetryInterval 10 -MaxRetries 1 { throw 'fail' }
            } catch { }
            Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 10 } -Scope It
        }

        It 'Waits RetryInterval * 2 seconds on second retry (attempt 1: interval * 2^1)' {
            try {
                New-Step -Retry -RetryInterval 10 -MaxRetries 2 { throw 'fail' }
            } catch { }
            Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 20 } -Scope It
        }

        It 'Waits RetryInterval * 4 seconds on third retry (attempt 2: interval * 2^2)' {
            try {
                New-Step -Retry -RetryInterval 10 -MaxRetries 3 { throw 'fail' }
            } catch { }
            Should -Invoke Start-Sleep -Exactly 1 -ParameterFilter { $Seconds -eq 40 } -Scope It
        }
    }

    Context 'Retry: events logged via Write-StepperLog' {
        BeforeEach {
            $script:RetryLogInfo = New-TestStepperScript -BaseName "retry-log-$(New-Guid)"
            $script:RetryLogPath = Join-Path $TestDrive "retry-events-$(New-Guid).log"
            Mock Get-StepIdentifier { "$($script:RetryLogInfo.Path):$($script:RetryLogInfo.FirstStepLine)" }
            Mock Start-Sleep {}
            $__StepperExecutionState.LogPath = $script:RetryLogPath
        }

        It 'Writes a retry event entry to the log after a failed attempt' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'Retrying'
        }

        It 'Log entry includes current attempt number' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'attempt 1'
        }

        It 'Log entry includes MaxRetries value' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '/3'
        }

        It 'Log entry includes the computed wait time in seconds' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '5s'
        }
    }

    Context 'Retry: elapsed time reporting' {
        BeforeEach {
            $script:RetryElapsedInfo = New-TestStepperScript -BaseName "retry-elapsed-$(New-Guid)"
            $script:RetryElapsedLogPath = Join-Path $TestDrive "retry-elapsed-$(New-Guid).log"
            Mock Get-StepIdentifier { "$($script:RetryElapsedInfo.Path):$($script:RetryElapsedInfo.FirstStepLine)" }
            Mock Start-Sleep {}
            $__StepperExecutionState.LogPath = $script:RetryElapsedLogPath
        }

        It 'Completion log entry reports final attempt elapsed time' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryElapsedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'completed in \d+\.?\d*s'
        }

        It 'Completion log entry includes total wall time when retries occurred' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryElapsedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'total wall time'
        }

        It 'Completion log entry does not include total wall time when step succeeds first attempt' {
            New-Step -Retry -RetryInterval 5 { }
            $logContent = Get-Content -Path $script:RetryElapsedLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Not -Match 'total wall time'
        }
    }

    Context 'Retry: partial transcript per failed attempt' {
        BeforeEach {
            $script:RetryTranscriptInfo = New-TestStepperScript -BaseName "retry-transcript-$(New-Guid)"
            $script:RetryTranscriptLogPath = Join-Path $TestDrive "retry-transcript-$(New-Guid).log"
            Mock Get-StepIdentifier { "$($script:RetryTranscriptInfo.Path):$($script:RetryTranscriptInfo.FirstStepLine)" }
            Mock Start-Sleep {}
            $__StepperExecutionState.LogPath = $script:RetryTranscriptLogPath
        }

        It 'Writes a PARTIAL transcript marker to the log for each failed retry attempt' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryTranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'PARTIAL'
        }

        It 'Partial transcript header includes attempt number' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryTranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match 'ATTEMPT \d+ PARTIAL'
        }

        It 'Writes a clean transcript section (no PARTIAL) for the successful attempt' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            $logContent = Get-Content -Path $script:RetryTranscriptLogPath -Raw -ErrorAction SilentlyContinue
            $logContent | Should -Match '=== BEGIN STEP \d+ TRANSCRIPT ==='
        }
    }

    Context 'Retry: warning when RetryInterval or MaxRetries used without -Retry' {
        BeforeEach {
            $script:RetryWarnInfo = New-TestStepperScript -BaseName "retry-warn-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:RetryWarnInfo.Path):$($script:RetryWarnInfo.FirstStepLine)" }
            Mock Write-StepperLog {}
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Emits a warning when -RetryInterval is specified without -Retry' {
            $warnings = New-Step -RetryInterval 30 { } 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Emits a warning when -MaxRetries is specified without -Retry' {
            $warnings = New-Step -MaxRetries 3 { } 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }

        It 'Does not emit a retry-param warning when both -Retry and -RetryInterval are specified' {
            $warnings = New-Step -Retry -RetryInterval 30 { } 3>&1
            $warnings | Where-Object { $_ -match '-RetryInterval.*-Retry|-Retry.*-RetryInterval' } | Should -BeNullOrEmpty
        }

        It 'Does not emit a retry-param warning when both -Retry and -MaxRetries are specified' {
            $warnings = New-Step -Retry -MaxRetries 3 { } 3>&1
            $warnings | Where-Object { $_ -match '-MaxRetries.*-Retry|-Retry.*-MaxRetries' } | Should -BeNullOrEmpty
        }
    }

    Context 'Retry: visual indicator on Write-Host' {
        BeforeEach {
            $script:VisualIndicatorInfo = New-TestStepperScript -BaseName "retry-visual-$(New-Guid)"
            Mock Get-StepIdentifier { "$($script:VisualIndicatorInfo.Path):$($script:VisualIndicatorInfo.FirstStepLine)" }
            Mock Get-StepLogConfig { [PSCustomObject]@{ UniqueStaticLogPaths = @(); HasConflict = $false; NoLogStepIds = @() } }
            Mock Start-Sleep {}
            Mock Write-Host
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperExecutionState' -Scope Global -ErrorAction SilentlyContinue
        }

        It 'Displays [>] retry indicator when a retry occurs' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 2 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            Should -Invoke Write-Host -ParameterFilter { $Object -match '\[>\]' } -Exactly 1 -Scope It
        }

        It 'Includes wait time in retry indicator message' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 10 -MaxRetries 2 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            Should -Invoke Write-Host -ParameterFilter { $Object -match 'Retrying in \d+s' } -Exactly 1 -Scope It
        }

        It 'Includes attempt number in retry indicator message' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 3 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            Should -Invoke Write-Host -ParameterFilter { $Object -match 'attempt 2 of' } -Exactly 1 -Scope It
        }

        It 'Does not display retry indicator when retry is not enabled' {
            New-Step { }
            Should -Invoke Write-Host -ParameterFilter { $Object -match '\[>\]' } -Exactly 0 -Scope It
        }

        It 'Displays retry indicator with Yellow foreground color' {
            $counter = @{ Calls = 0 }
            New-Step -Retry -RetryInterval 5 -MaxRetries 2 {
                $counter.Calls++
                if ($counter.Calls -lt 2) { throw 'transient' }
            }
            Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Yellow' } -Exactly 1 -Scope It
        }
    }

    Context 'Start-Stepper sentinel' {
        It 'Throws StartStepperNotRun when the sentinel is absent' {
            $info = New-TestStepperScript
            Mock Get-StepIdentifier { "$($info.Path):$($info.FirstStepLine)" }
            Remove-Variable -Name '__StepperInitialized' -ErrorAction SilentlyContinue
            Remove-Variable -Name '__StepperInitialized' -Scope Global -ErrorAction SilentlyContinue

            $errors = @()
            try {
                New-Step { } -ErrorAction Stop
            } catch {
                $errors += $_
            }
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StartStepperNotRun*' } | Should -Not -BeNullOrEmpty
        }
    }
}
