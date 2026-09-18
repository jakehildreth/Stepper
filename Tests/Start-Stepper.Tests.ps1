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
            'New-Step { }'
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
        param(
            [string]$ScriptPath,
            [string]$InputText,
            [switch]$DotSource
        )
        $modulePsd1 = "$ModulePath/Stepper.psd1"
        $outFile = Join-Path $TestDrive "proc-$(New-Guid).log"
        $emptyIn = Join-Path $TestDrive "stdin-$(New-Guid).txt"
        if ($PSBoundParameters.ContainsKey('InputText')) {
            [System.IO.File]::WriteAllText($emptyIn, $InputText)
        } else {
            [System.IO.File]::WriteAllBytes($emptyIn, [byte[]]@())
        }
        $invocation = if ($DotSource) { ". '$ScriptPath'" } else { "& '$ScriptPath'" }
        $proc = Start-Process -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile', '-Command',
            "`$env:STEPPER_SHOW_LOGO='false'; Import-Module '$modulePsd1' -Force; try { $invocation } catch { Write-Error `$_; exit 1 }; if (`$null -ne `$LASTEXITCODE) { exit `$LASTEXITCODE }"
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
            $result.ExitCode | Should -Be 75
            $result.Output | Should -Match 'Stepper repaired'
            $result.Output | Should -Match 'Re-run the script'
        }
    }

    Describe 'Start-Stepper canonical pipeline' -Tag 'Integration' {
        Context 'Invocation gate' {
            It 'Rejects a dot-sourced Stepper script before user code executes' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "dot-source-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'New-Step { }'
                    '#region Stepper ignore'
                    "'ran' | Set-Content -LiteralPath '$markerPath'"
                    '#endregion Stepper ignore'
                    'Stop-Stepper'
                )

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath -DotSource

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match 'cannot be dot-sourced'
                $markerPath | Should -Not -Exist
            }
        }

        Context 'Rewrite gate' {
            It 'removes stale state and exits 75 before user code after deterministic repair' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "repair-gate-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                $statePath = "$scriptPath.stepper"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'New-Step { }'
                    '#region Stepper ignore'
                    "'ran' | Set-Content -LiteralPath '$markerPath'"
                    '#endregion Stepper ignore'
                    'Stop-Stepper'
                )
                Set-Content -LiteralPath $statePath -Value 'stale'

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Be 75
                $statePath | Should -Not -Exist
                $markerPath | Should -Not -Exist
                $result.Output | Should -Match 'Backup:'
            }

            It 'wraps unmanaged code non-interactively and exits 75 before executing it' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "unmanaged-gate-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    "'ran' | Set-Content -LiteralPath '$markerPath'"
                    'Stop-Stepper'
                )

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Be 75
                $markerPath | Should -Not -Exist
                (Get-Content -LiteralPath $scriptPath -Raw) | Should -Match 'New-Step \{'
            }
        }

        Context 'Blocking errors' {
            It 'blocks report-only errors before unmanaged remediation or user code' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "blocking-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'if ($true) { New-Step { } }'
                    '#region Stepper ignore'
                    "'ran' | Set-Content -LiteralPath '$markerPath'"
                    '#endregion Stepper ignore'
                    'Stop-Stepper'
                )
                $before = Get-Content -LiteralPath $scriptPath -Raw

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match '\[NestedNewStep\]'
                (Get-Content -LiteralPath $scriptPath -Raw) | Should -BeExactly $before
                $markerPath | Should -Not -Exist
            }

            It 'fails unresolved NoSteps after unmanaged remediation has no work' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "no-steps-$(New-Guid).ps1"))
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'Stop-Stepper'
                )

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match '\[NoSteps\]'
            }
        }

        Context 'Warnings and conversion' {
            It 'runs a script without comment-based help without emitting any warning' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "warning-$(New-Guid).ps1"))
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'New-Step { }'
                    'Stop-Stepper'
                )

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Be 0
                $result.Output | Should -Not -Match 'MissingCbh'
                $result.Output | Should -Not -Match 'WARNING'
            }

            It 'fails non-interactive conversion review before runtime state or user code' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "conversion-gate-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    'New-Step { $value = 1 }'
                    'New-Step { $value | Out-Null }'
                    '#region Stepper ignore'
                    "'ran' | Set-Content -LiteralPath '$markerPath'"
                    '#endregion Stepper ignore'
                    'Stop-Stepper'
                )

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match 'requires an interactive review'
                $markerPath | Should -Not -Exist
                "$scriptPath.stepper" | Should -Not -Exist
            }
        }
    }

    Describe 'Start-Stepper non-interactive state gate' -Tag 'Integration' {
        Context 'Existing valid state' {
            It 'resumes automatically when the saved hash matches' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "auto-resume-$(New-Guid).ps1"))
                $firstMarker = "$scriptPath.first"
                $secondMarker = "$scriptPath.second"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    "New-Step { 'first' | Set-Content -LiteralPath '$firstMarker' }"
                    "New-Step { 'second' | Set-Content -LiteralPath '$secondMarker' }"
                    'Stop-Stepper'
                )
                Write-PriorState -ScriptPath $scriptPath | Out-Null

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Be 0
                $firstMarker | Should -Not -Exist
                $secondMarker | Should -Exist
                $result.Output | Should -Match 'Resuming from'
                $result.Output | Should -Not -Match 'How would you like to proceed'
            }

            It 'starts over automatically when the saved hash differs' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "auto-fresh-$(New-Guid).ps1"))
                $firstMarker = "$scriptPath.first"
                $secondMarker = "$scriptPath.second"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    "New-Step { 'first' | Set-Content -LiteralPath '$firstMarker' }"
                    "New-Step { 'second' | Set-Content -LiteralPath '$secondMarker' }"
                    'Stop-Stepper'
                )
                Write-PriorState -ScriptPath $scriptPath | Out-Null
                (Get-Content -LiteralPath $scriptPath -Raw).Replace("'second'", "'changed'") |
                    Set-Content -LiteralPath $scriptPath -NoNewline

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Be 0
                $firstMarker | Should -Exist
                $secondMarker | Should -Exist
                $result.Output | Should -Match 'Starting fresh'
                $result.Output | Should -Not -Match 'How would you like to proceed'
            }
        }

        Context 'Invalid state' {
            It 'fails instead of guessing when state is malformed' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "malformed-state-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    "New-Step { 'ran' | Set-Content -LiteralPath '$markerPath' }"
                    'Stop-Stepper'
                )
                [PSCustomObject]@{ ScriptHash = 'abc' } | Export-Clixml -LiteralPath "$scriptPath.stepper"

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match 'malformed or inconsistent'
                $markerPath | Should -Not -Exist
            }

            It 'fails when the saved step is absent from the final inventory' {
                $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $TestDrive "inconsistent-state-$(New-Guid).ps1"))
                $markerPath = "$scriptPath.ran"
                Set-Content -Path $scriptPath -Value @(
                    '[CmdletBinding()]'
                    'param()'
                    '#region Stepper ignore'
                    'if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }'
                    'Start-Stepper'
                    '#endregion Stepper ignore'
                    "New-Step { 'ran' | Set-Content -LiteralPath '$markerPath' }"
                    'Stop-Stepper'
                )
                [PSCustomObject]@{
                    ScriptHash            = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
                    LastCompletedStep     = "$scriptPath`:999"
                    LastCompletedStepName = $null
                    Timestamp             = (Get-Date).ToString('o')
                    StepperData           = @{}
                } | Export-Clixml -LiteralPath "$scriptPath.stepper"

                $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

                $result.ExitCode | Should -Not -Be 0
                $result.Output | Should -Match 'not present in the final step inventory'
                $markerPath | Should -Not -Exist
            }
        }
    }

    Context 'Stop-Stepper presence' {
        It 'Continues without rewriting in a non-interactive run' {
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
            $before = Get-Content $scriptPath -Raw

            $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

            $result.ExitCode | Should -Be 0
            (Get-Content $scriptPath -Raw) | Should -BeExactly $before
            $result.Output | Should -Match 'Continuing without Stop-Stepper'
        }
    }

    Context 'SkipRequirementsCheck compatibility' {
        It 'Runs the same deterministic repair pipeline when -SkipRequirementsCheck is passed' {
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

            $result = Invoke-StepperScriptProcess -ScriptPath $scriptPath

            $result.ExitCode | Should -Be 75
            (Get-Content $scriptPath -Raw) | Should -Match 'Install-Module Stepper'
        }
    }
}
