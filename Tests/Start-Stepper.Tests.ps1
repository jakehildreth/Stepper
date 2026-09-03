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
