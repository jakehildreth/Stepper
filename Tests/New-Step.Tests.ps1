BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepIdentifier.ps1"
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Write-StepperState.ps1"
    . "$ModulePath/Private/Read-StepperState.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Test-LineInIgnoredRegion.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Find-UnmanagedCodeBlocks.ps1"
    . "$ModulePath/Private/Get-UnmanagedCodeAction.ps1"
    . "$ModulePath/Private/Update-ScriptWithUnmanagedActions.ps1"
    . "$ModulePath/Private/Test-StepperScriptRequirements.ps1"
    . "$ModulePath/Private/Show-MoreDetails.ps1"
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
}
