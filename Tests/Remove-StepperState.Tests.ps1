BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Remove-StepperState.ps1"
}

Describe 'Remove-StepperState' -Tag 'Unit' {
    Context 'When state file exists' {
        It 'Should remove the state file from disk' {
            $statePath = Join-Path $TestDrive 'existing.stepper'
            Set-Content -Path $statePath -Value 'state data'
            Remove-StepperState -StatePath $statePath
            $statePath | Should -Not -Exist
        }
    }

    Context 'When state file does not exist' {
        It 'Should not throw (idempotent)' {
            $nonExistentPath = Join-Path $TestDrive 'ghost.stepper'
            { Remove-StepperState -StatePath $nonExistentPath } | Should -Not -Throw
        }
    }

    Context 'When Remove-Item fails' {
        BeforeAll {
            $script:LockedPath = Join-Path $TestDrive 'locked.stepper'
            Set-Content -Path $script:LockedPath -Value 'state data'
            Mock Remove-Item { throw [System.IO.IOException]::new('access denied') }
        }

        It 'Should write a non-terminating error with StateRemovalFailed error id' {
            $errors = @()
            Remove-StepperState -StatePath $script:LockedPath -ErrorVariable errors -ErrorAction SilentlyContinue
            $errors | Where-Object { $_.FullyQualifiedErrorId -like 'StateRemovalFailed*' } | Should -Not -BeNullOrEmpty
        }
    }
}
