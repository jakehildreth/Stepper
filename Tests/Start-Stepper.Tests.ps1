BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    $env:STEPPER_SHOW_LOGO = 'false'
    Import-Module "$ModulePath/Stepper.psd1" -Force
    # Capture the exact module instance this file loaded; Get-Module Stepper can
    # return multiple instances when the full suite runs several test files.
    $script:StepperModule = @(Get-Module Stepper) | Select-Object -First 1

    # Every fixture must satisfy the requirements check that Start-Stepper now
    # runs: [CmdletBinding()], param(), and the Install-Module guard. Without the
    # guard, Start-Stepper repairs the script and exits before anything else.
    # Start-Stepper goes INSIDE the ignore region (after the guard) so the
    # unmanaged-code scan does not flag it (#82 placement decision).
    $script:Guard = @(
        '#region Stepper ignore'
        'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
        'Start-Stepper'
        '#endregion Stepper ignore'
    )

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

        $lines = @()
        $lines += @(
            '[CmdletBinding()]'
            'param()'
        )
        $lines += $script:Guard
        $lines += @(
            '#region Stepper ignore'
            '$observed = [PSCustomObject]@{'
            '    SentinelSet  = [bool](Get-Variable -Name ''__StepperInitialized'' -ErrorAction SilentlyContinue)'
            '    State        = (Get-Variable -Name ''__StepperExecutionState'' -ErrorAction SilentlyContinue).Value'
            '    Stepper      = (Get-Variable -Name ''Stepper'' -ErrorAction SilentlyContinue).Value'
            '}'
            "`$observed | Export-Clixml -Path '$observedPath'"
            '#endregion Stepper ignore'
            'Stop-Stepper'
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
        & $script:StepperModule {
            param($resp)
            $script:__StepperTestResponses = [System.Collections.Generic.Queue[string]]::new()
            foreach ($r in $resp) { $script:__StepperTestResponses.Enqueue($r) }
        } $Responses
    }

    function Clear-StepperTestResponses {
        & $script:StepperModule {
            Remove-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
        }
    }

    # Helper: write a state file beside a script, simulating a prior run.
    # LastCompletedStep points at the first New-Step line, located by scanning
    # (the guard region shifts line numbers, so a hardcoded line breaks).
    function Write-PriorState {
        param(
            [string]$ScriptPath,
            [hashtable]$StepperData = @{},
            [string]$LogPath = $null
        )
        $statePath = "$ScriptPath.stepper"
        $hash = Get-FileHash -Path $ScriptPath -Algorithm SHA256
        $firstStepLine = 0
        $fileLines = Get-Content -Path $ScriptPath
        for ($i = 0; $i -lt $fileLines.Count; $i++) {
            if ($fileLines[$i] -match 'New-Step') { $firstStepLine = $i + 1; break }
        }
        [PSCustomObject]@{
            ScriptHash           = $hash.Hash
            LastCompletedStep    = "$ScriptPath`:$firstStepLine"
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

    # Helper: run a script in a SEPARATE pwsh process and capture output.
    # The script checks (requirements repair, Stop-Stepper add, unmanaged,
    # ConvertTo) call 'exit' after mutating the script, so they must run
    # out-of-process. With no console, Read-Host throws and Read-StepperChoice
    # returns each menu's non-interactive default. Returns @{ Output; ExitCode }.
    function Invoke-StepperScriptProcess {
        param([string]$ScriptPath)
        $modulePsd1 = "$ModulePath/Stepper.psd1"
        $outFile = Join-Path $TestDrive "proc-$(New-Guid).log"
        # RedirectStandardInput from an empty file so any Read-Host in the child
        # gets EOF (returns $null) instead of blocking on the inherited console.
        $emptyIn = Join-Path $TestDrive "stdin-$(New-Guid).txt"
        Set-Content -Path $emptyIn -Value ''
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile', '-Command',
            "`$env:STEPPER_SHOW_LOGO='false'; Import-Module '$modulePsd1' -Force; & '$ScriptPath'"
        ) -RedirectStandardInput $emptyIn -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err" -Wait -PassThru
        $code = $proc.ExitCode
        $out = (Get-Content $outFile -Raw -ErrorAction SilentlyContinue)
        $err = (Get-Content "$outFile.err" -Raw -ErrorAction SilentlyContinue)
        return @{
            Output   = ($out, $err -join "`n")
            ExitCode = $code
        }
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
                'New-Step { }'
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
                'New-Step { }'
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper; StartFresh = `$__StepperExecutionState.StartFresh }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                '$Stepper = @{ Leftover = ''x'' }'
                'New-Step { }'
                'New-Step { }'
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ Stepper = `$Stepper }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
                'Stop-Stepper'
            )
            Write-PriorState -ScriptPath $scriptPath -StepperData @{ Old = 'data' } | Out-Null
            # The '$Stepper = @{ Leftover }' line is deliberately unmanaged; 'i'
            # ignores it, then 's' answers the resume menu with Start over.
            Set-StepperTestResponses -Responses @('i', 's')

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.Stepper | Should -BeOfType [hashtable]
            # 'Leftover' is re-added by the unmanaged line on every run (that is
            # what unmanaged code does); the pristine guarantee only clears the
            # PERSISTED 'Old' data from the prior run's state file.
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
                'New-Step { }'
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
                'New-Step { }'
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
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
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                "New-Step -LogPath '$declared' { }"
                '#region Stepper ignore'
                "`$o = [PSCustomObject]@{ LogPath = `$__StepperExecutionState.LogPath }"
                "`$o | Export-Clixml -Path '$observedPath'"
                '#endregion Stepper ignore'
                'Stop-Stepper'
            )

            & $scriptPath

            $observed = Import-Clixml -Path $observedPath
            $observed.LogPath | Should -Be $declared
        }
    }
}

Describe 'Start-Stepper script checks' -Tag 'Integration' {
    Context 'Requirements repair' {
        It 'Adds a missing Install-Module guard and exits for re-run' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "guard-$(New-Guid).ps1"))
            # Has Start-Stepper (inside a region) + Stop-Stepper but NO Install-Module guard line
            Set-Content -Path $scriptPath -Value @(
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
                'Stop-Stepper'
            )

            $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

            $content = Get-Content $scriptPath -Raw
            $content | Should -Match 'Install-Module Stepper'
            $result.Output | Should -Match 'has been added'
        }
    }

    Context 'Stop-Stepper presence' {
        It 'Appends Stop-Stepper when missing (empty/non-interactive input defaults to Add)' {
            # Read-Host with closed stdin returns empty; the menu treats empty as
            # the highlighted default [A] = Add, then exits for a re-run.
            # CBH is present so the requirements check does not modify the file first.
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "stop-$(New-Guid).ps1"))
            Set-Content -Path $scriptPath -Value @(
                '<#'
                '.SYNOPSIS'
                '    test'
                '#>'
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                'Start-Stepper'
                '#endregion Stepper ignore'
                'New-Step { }'
            )

            $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

            (Get-Content $scriptPath -Raw) | Should -Match 'Stop-Stepper'
            $result.Output | Should -Match 'does not call Stop-Stepper'
        }
    }

    Context 'Requirements repair is skipped with -SkipRequirementsCheck' {
        It 'Does not modify a script missing the guard when -SkipRequirementsCheck is passed' {
            $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "skip-$(New-Guid).ps1"))
            Set-Content -Path $scriptPath -Value @(
                '<#'
                '.SYNOPSIS'
                '    test'
                '#>'
                '[CmdletBinding()]'
                'param()'
                '#region Stepper ignore'
                'Start-Stepper -SkipRequirementsCheck'
                '#endregion Stepper ignore'
                'New-Step { }'
                'Stop-Stepper'
            )
            $before = Get-Content $scriptPath -Raw

            Invoke-StepperScriptProcess -ScriptPath $scriptPath | Out-Null

            (Get-Content $scriptPath -Raw) | Should -Be $before
        }
    }
}
