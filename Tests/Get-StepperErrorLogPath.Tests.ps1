BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperErrorLogPath.ps1"
}

Describe 'Get-StepperErrorLogPath' -Tag 'Unit' {
    It 'Inserts .errors before the extension for the default log name' {
        $logPath = Join-Path $TestDrive 'script.ps1.stepper.log'
        Get-StepperErrorLogPath -LogPath $logPath |
            Should -Be (Join-Path $TestDrive 'script.ps1.stepper.errors.log')
    }

    It 'Inserts .errors before the extension for a custom log path' {
        $logPath = Join-Path $TestDrive 'deploy.log'
        Get-StepperErrorLogPath -LogPath $logPath |
            Should -Be (Join-Path $TestDrive 'deploy.errors.log')
    }

    It 'Appends .errors.log when the log path has no extension' {
        $logPath = Join-Path $TestDrive 'deploy'
        Get-StepperErrorLogPath -LogPath $logPath |
            Should -Be (Join-Path $TestDrive 'deploy.errors.log')
    }

    It 'Keeps the log directory' {
        $logPath = Join-Path (Join-Path $TestDrive 'logs') 'deploy.txt'
        Get-StepperErrorLogPath -LogPath $logPath |
            Should -Be (Join-Path (Join-Path $TestDrive 'logs') 'deploy.errors.txt')
    }

    It 'Returns null when the log path is empty' {
        Get-StepperErrorLogPath -LogPath '' | Should -BeNullOrEmpty
    }
}
