BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperErrorDelta.ps1"
}

Describe 'Get-StepperErrorDelta' -Tag 'Unit' {
    BeforeEach {
        $global:Error.Clear()
    }

    AfterEach {
        $global:Error.Clear()
    }

    It 'Returns every error when the baseline is null' {
        Write-Error 'first' -ErrorAction SilentlyContinue
        Write-Error 'second' -ErrorAction SilentlyContinue

        @(Get-StepperErrorDelta -Baseline $null) | Should -HaveCount 2
    }

    It 'Returns only errors added after the baseline' {
        Write-Error 'old' -ErrorAction SilentlyContinue
        $baseline = $global:Error[0]
        Write-Error 'new one' -ErrorAction SilentlyContinue
        Write-Error 'new two' -ErrorAction SilentlyContinue

        $delta = @(Get-StepperErrorDelta -Baseline $baseline)

        $delta | Should -HaveCount 2
        $delta.Exception.Message | Should -Not -Contain 'old'
    }

    It 'Returns nothing when no errors were added after the baseline' {
        Write-Error 'old' -ErrorAction SilentlyContinue
        $baseline = $global:Error[0]

        @(Get-StepperErrorDelta -Baseline $baseline) | Should -HaveCount 0
    }

    It 'Returns nothing when $Error is empty' {
        @(Get-StepperErrorDelta -Baseline $null) | Should -HaveCount 0
    }
}
