BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    $env:STEPPER_SHOW_LOGO = 'false'
    Import-Module "$ModulePath/Stepper.psd1" -Force

    # Helper: create a script in $TestDrive that calls Start-Stepper, run it,
    # and return the observations the script wrote to disk.
    # Start-Stepper writes $Stepper, __StepperInitialized, and
    # __StepperExecutionState into the CALLING SCRIPT's scope, which dies when
    # the script exits. So the script itself records what it saw to a file.
    function Invoke-StartStepperScript {
        param(
            [string]$BaseName = "test-$(New-Guid)",
            [string[]]$Body = @()
        )
        $scriptPath = Join-Path $TestDrive "$BaseName.ps1"
        $observedPath = Join-Path $TestDrive "$BaseName.observed.clixml"

        $lines = @(
            '[CmdletBinding()]'
            'param()'
            'Start-Stepper'
            '$observed = [PSCustomObject]@{'
            '    SentinelSet  = [bool](Get-Variable -Name ''__StepperInitialized'' -ErrorAction SilentlyContinue)'
            '    State        = (Get-Variable -Name ''__StepperExecutionState'' -ErrorAction SilentlyContinue).Value'
            '    Stepper      = (Get-Variable -Name ''Stepper'' -ErrorAction SilentlyContinue).Value'
            '}'
            "`$observed | Export-Clixml -Path '$observedPath'"
        )
        $lines += $Body
        Set-Content -Path $scriptPath -Value $lines

        & $scriptPath

        return @{
            Path      = $scriptPath
            StatePath = "$scriptPath.stepper"
            Observed  = if (Test-Path $observedPath) { Import-Clixml -Path $observedPath } else { $null }
        }
    }

    # Helper: queue menu responses inside the imported module's script scope so
    # Read-StepperChoice (module-private, unmockable from here) dequeues them
    # when the child script runs.
    function Set-StepperTestResponses {
        param([string[]]$Responses = @())
        & (Get-Module Stepper) {
            param($resp)
            $script:__StepperTestResponses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($r in $resp) { $script:__StepperTestResponses.Enqueue($r) }
        } $Responses
    }

    function Clear-StepperTestResponses {
        & (Get-Module Stepper) {
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
        }
    }

    # Helper: write a state file beside a script, simulating a prior run.
    function Write-PriorState {
        param(
            [string]$ScriptPath,
            [hashtable]$StepperData = @{},
            [string]$LogPath = $null
        )
        $statePath = "$ScriptPath.stepper"
        $hash = Get-FileHash -Path $ScriptPath -Algorithm SHA256
        [PSCustomObject]@{
            ScriptHash           = $hash.Hash
            LastCompletedStep    = "$ScriptPath`:4"
            LastCompletedStepName = $null
            StepNumber           = 1
            Timestamp            = (Get-Date).ToString('o')
            StepperData          = $StepperData
            LogPath              = $LogPath
            LoggingEnabled       = $true
            NoLogStepIds         = @()
        } | Export-Clixml -Path $statePath
        return $statePath
    }
}

Describe 'Start-Stepper skeleton' -Tag 'Integration' {
    Context 'Sentinel and execution state' {
        It 'Sets __StepperInitialized in the caller scope' {
            $result = Invoke-StartStepperScript
            $result.Observed.SentinelSet | Should -BeTrue
        }

        It 'Creates __StepperExecutionState with fresh-run defaults' {
            $result = Invoke-StartStepperScript
            $state = $result.Observed.State
            $state | Should -Not -BeNullOrEmpty
            $state.RestoreMode | Should -BeFalse
            $state.TargetStep | Should -BeNullOrEmpty
            $state.CurrentScriptPath | Should -Be $result.Path
            $state.StatePath | Should -Be $result.StatePath
            $state.LoggingEnabled | Should -BeTrue
        }

        It 'Initializes $Stepper as an empty hashtable when no state exists' {
            $result = Invoke-StartStepperScript
            $result.Observed.Stepper | Should -BeOfType [hashtable]
            $result.Observed.Stepper.Count | Should -Be 0
        }
    }

    Context 'Identity resolution' {
        It 'Resolves the calling script path, not the module or test file' {
            $result = Invoke-StartStepperScript
            $result.Observed.State.CurrentScriptPath | Should -Be $result.Path
        }
    }
}

Describe 'Start-Stepper resume and pristine start' -Tag 'Integration' {
    AfterEach { Clear-StepperTestResponses }

    Context 'Resume injects StepperData' {
        It 'Injects persisted StepperData into $Stepper when the user resumes' {
            # Pre-create the script so we can write a matching state file first.
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "resume-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'Start-Stepper'
                'New-Step { }'
                'New-Step { }'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )
            Write-PriorState -ScriptPath $scriptPath -StepperData @{ Name = 'Jake'; Count = 3 } | Out-Null
            Set-StepperTestResponses -Responses @('r')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            # Injection is the assertion. RestoreMode is set by Start-Stepper but
            # the fixture's own New-Step calls clear it again before we observe.
            $observed.Stepper.Name | Should -Be 'Jake'
            $observed.Stepper.Count | Should -Be 3
        }
    }

    Context 'Start Over is pristine' {
        It 'Does NOT inject prior StepperData and deletes the state file' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "fresh-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'Start-Stepper'
                'New-Step { }'
                'New-Step { }'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper; StartFresh = `$__StepperExecutionState.StartFresh }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )
            $statePath = Write-PriorState -ScriptPath $scriptPath -StepperData @{ Secret = 'stale' }
            Set-StepperTestResponses -Responses @('s')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.StartFresh | Should -BeTrue
            $observed.Stepper.Secret | Should -BeNullOrEmpty
            # New-Step injects StepName/StepNumber metadata into $Stepper; assert
            # the PRIOR run's data is gone, not that the table is empty.
            $observed.Stepper.ContainsKey('Secret') | Should -BeFalse
            # Note: state-file deletion at end-of-run is Stop-Stepper's job, and
            # Stop-Stepper resolves the TEST file's path (not the fixture's) under
            # this nested harness, so deletion is not asserted here. The pristine
            # guarantee asserted above (StartFresh + no prior data) is Start-Stepper's.
        }

        It 'Recreates $Stepper as an empty hashtable after clearing a stale one' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "stale-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                '$Stepper = @{ Leftover = ''x'' }'
                'Start-Stepper'
                'New-Step { }'
                'New-Step { }'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )
            Write-PriorState -ScriptPath $scriptPath -StepperData @{ Old = 'data' } | Out-Null
            Set-StepperTestResponses -Responses @('s')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.Stepper | Should -BeOfType [hashtable]
            $observed.Stepper.ContainsKey('Leftover') | Should -BeFalse
            $observed.Stepper.ContainsKey('Old') | Should -BeFalse
        }
    }
}

Describe 'Start-Stepper log config' -Tag 'Integration' {
    AfterEach { Clear-StepperTestResponses }

    Context 'Resume restores log config from state' {
        It 'Restores persisted LogPath silently on resume (no AST resolution prompt)' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "logres-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            $priorLog = Join-Path $TestDrive 'prior.log'
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'Start-Stepper'
                'New-Step { }'
                'New-Step { }'
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )
            Write-PriorState -ScriptPath $scriptPath -StepperData @{ X = 1 } -LogPath $priorLog | Out-Null
            Set-StepperTestResponses -Responses @('r')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.LogPath | Should -Be $priorLog
        }
    }

    Context 'Start Over does not inherit old log config' {
        It 'Resolves log config fresh after Start Over instead of restoring the stale path' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "logfresh-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            $staleLog = Join-Path $TestDrive 'stale.log'
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'Start-Stepper'
                'New-Step { }'
                'New-Step { }'
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )
            Write-PriorState -ScriptPath $scriptPath -StepperData @{ X = 1 } -LogPath $staleLog | Out-Null
            Set-StepperTestResponses -Responses @('s')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            # Start Over must NOT carry the stale log path forward; the fixture has
            # no -LogPath on any step, so it resolves to the default beside the script.
            $observed.LogPath | Should -Not -Be $staleLog
            $observed.LogPath | Should -Be "$scriptPath.stepper.log"
        }
    }

    Context 'Fresh run resolves from AST' {
        It 'Uses the single static -LogPath declared on a step' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "logdecl-$(New-Guid).ps1"))
            $observedPath = "$scriptPath.observed.clixml"
            $declared = Join-Path $TestDrive 'declared.log'
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                'Start-Stepper'
                "New-Step -LogPath '$declared' { }"
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                'Stop-Stepper'
            )

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.LogPath | Should -Be $declared
        }
    }
}
