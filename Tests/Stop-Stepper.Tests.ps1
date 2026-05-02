BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
    . "$ModulePath/Private/Write-StepperState.ps1"
    . "$ModulePath/Private/Read-StepperState.ps1"
    . "$ModulePath/Private/Remove-StepperState.ps1"
    . "$ModulePath/Private/Write-StepperLog.ps1"
    . "$ModulePath/Public/Stop-Stepper.ps1"

    # On macOS, $TestDrive resolves to /private/tmp/… which matches the
    # */Private/*.ps1 path filter in Stop-Stepper (case-insensitive -like).
    # Use the test file's own path as the fake "user script" ScriptName — it
    # lives in Tests/ and will never match Private/, Public/, or Stepper.psm1.
    $script:FakeUserScript = Join-Path $PSScriptRoot 'Stop-Stepper.Tests.ps1'
    $script:FakeStatePath  = Get-StepperStatePath -ScriptPath $script:FakeUserScript
}

Describe 'Stop-Stepper' -Tag 'Integration' {
    BeforeAll {
        Mock Write-Host {}
        Mock Write-Verbose {}
    }

    AfterEach {
        Remove-Item -Path $script:FakeStatePath -ErrorAction SilentlyContinue
    }

    Context 'When state file exists for the calling script' {
        BeforeEach {
            Write-StepperState -StatePath $script:FakeStatePath -ScriptHash 'abc123' `
                -LastCompletedStep "${script:FakeUserScript}:1"

            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser  = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
        }

        It 'Removes the state file' {
            Stop-Stepper
            $script:FakeStatePath | Should -Not -Exist
        }
    }

    Context 'When no state file exists' {
        BeforeEach {
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser  = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
        }

        It 'Does not throw' {
            { Stop-Stepper } | Should -Not -Throw
        }
    }

    Context 'When call stack has only module frames' {
        BeforeEach {
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
        }

        It 'Writes a warning about unable to determine script path' {
            Mock Write-Warning {}
            Stop-Stepper
            Should -Invoke Write-Warning -Exactly 1 -ParameterFilter {
                $Message -like '*Unable to determine*'
            } -Scope It
        }
    }

    Context 'When call stack includes mixed module frames before user script' {
        BeforeEach {
            Write-StepperState -StatePath $script:FakeStatePath -ScriptHash 'abc' `
                -LastCompletedStep "${script:FakeUserScript}:1"

            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser  = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Private${sep}Some-Helper.ps1"
                    ScriptLineNumber = 5
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Stepper.psm1"
                    ScriptLineNumber = 10
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
        }

        It 'Skips all module frames and finds the user script' {
            Stop-Stepper
            $script:FakeStatePath | Should -Not -Exist
        }
    }

    Context 'When script path falls back to __StepperExecutionState' {
        BeforeEach {
            Write-StepperState -StatePath $script:FakeStatePath -ScriptHash 'abc' `
                -LastCompletedStep "${script:FakeUserScript}:1"

            # Return only module frames — forces fallback to __StepperExecutionState
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()

            # Inject __StepperExecutionState into the current scope so Stop-Stepper's
            # $PSCmdlet.SessionState can find it
            $__StepperExecutionState = @{ CurrentScriptPath = $script:FakeUserScript }
        }

        It 'Resolves script path from __StepperExecutionState and removes state file' {
            Stop-Stepper
            $script:FakeStatePath | Should -Not -Exist
        }
    }

    Context 'When state removal throws' {
        BeforeEach {
            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser  = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
            Mock Remove-StepperState { throw 'simulated permission denied' }
        }

        It 'Writes a non-terminating error' {
            $result = Stop-Stepper 2>&1
            $errRecords = @($result | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $errRecords.Count | Should -Be 1
            $errRecords[0].Exception.Message | Should -Match 'Failed to clear Stepper state'
        }

        It 'Does not rethrow' {
            { Stop-Stepper 2>&1 | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Logging — summary entry written on completion' {
        BeforeEach {
            Write-StepperState -StatePath $script:FakeStatePath -ScriptHash 'abc123' `
                -LastCompletedStep "${script:FakeUserScript}:1"

            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser   = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
            Mock Write-StepperLog {}
        }

        It 'Should call Write-StepperLog on successful completion' {
            Stop-Stepper
            Should -Invoke Write-StepperLog -Scope It
        }

        It 'Should log the completion message' {
            Stop-Stepper
            Should -Invoke Write-StepperLog -Scope It -ParameterFilter {
                $Message -match 'All steps complete'
            }
        }
    }

    Context 'Logging — reads LogPath from execution state' {
        BeforeEach {
            Write-StepperState -StatePath $script:FakeStatePath -ScriptHash 'abc123' `
                -LastCompletedStep "${script:FakeUserScript}:1"

            $sep = [System.IO.Path]::DirectorySeparatorChar
            $modulePath = $ModulePath
            $fakeUser   = $script:FakeUserScript
            $frames = @(
                [PSCustomObject]@{
                    ScriptName       = "${modulePath}${sep}Public${sep}Stop-Stepper.ps1"
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                },
                [PSCustomObject]@{
                    ScriptName       = $fakeUser
                    ScriptLineNumber = 1
                    InvocationInfo   = [PSCustomObject]@{ BoundParameters = @{} }
                }
            )
            Mock Get-PSCallStack -MockWith { $frames }.GetNewClosure()
            Mock Write-StepperLog {}

            # Inject execution state with a known LogPath
            $__StepperExecutionState = @{
                CurrentScriptPath = $fakeUser
                LogPath           = Join-Path $TestDrive 'injected.log'
                LoggingEnabled    = $true
                NoLogStepIds      = @()
            }
        }

        It 'Should pass the LogPath from execution state to Write-StepperLog' {
            $expectedLog = Join-Path $TestDrive 'injected.log'
            Stop-Stepper
            Should -Invoke Write-StepperLog -Scope It -ParameterFilter {
                $LogPath -eq $expectedLog
            }
        }
    }
}
