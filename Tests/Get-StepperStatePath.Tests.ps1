BeforeAll {
    # Dot-source the private function directly for testing
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperStatePath.ps1"
}

Describe 'Get-StepperStatePath' {
    Context 'Cross-platform path handling' {
        It 'Should append .stepper extension' {
            $result = Get-StepperStatePath -ScriptPath '/home/user/scripts/test.ps1'
            $result | Should -Be '/home/user/scripts/test.ps1.stepper'
        }

        It 'Should handle paths with spaces' {
            $result = Get-StepperStatePath -ScriptPath '/home/user/my scripts/test script.ps1'
            $result | Should -Be '/home/user/my scripts/test script.ps1.stepper'
        }

        It 'Should handle nested directories' {
            $result = Get-StepperStatePath -ScriptPath '/projects/powershell/scripts/migration.ps1'
            $result | Should -Be '/projects/powershell/scripts/migration.ps1.stepper'
        }

        It 'Should handle relative paths' {
            $result = Get-StepperStatePath -ScriptPath './scripts/test.ps1'
            $result | Should -Be './scripts/test.ps1.stepper'
        }

        It 'Should handle script with multiple dots in name' {
            $result = Get-StepperStatePath -ScriptPath '/home/scripts/test.backup.ps1'
            $result | Should -Be '/home/scripts/test.backup.ps1.stepper'
        }
    }
}
