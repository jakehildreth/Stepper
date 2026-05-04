BeforeAll {
    . (Join-Path $PSScriptRoot '../Private/New-StepperBackup.ps1')
}

Describe 'New-StepperBackup' {
    BeforeAll {
        $script:TempDir  = [System.IO.Path]::GetTempPath()
        $script:BaseName = 'StepperBackupTest'
        $script:OrigPath = Join-Path $script:TempDir "$($script:BaseName).ps1"
        $script:OrigContent = 'New-Step { Write-Host "original" }'
        Set-Content -Path $script:OrigPath -Value $script:OrigContent -Encoding UTF8 -NoNewline
    }

    AfterAll {
        Remove-Item -Path $script:OrigPath -ErrorAction SilentlyContinue
        Get-ChildItem -Path $script:TempDir -Filter "$($script:BaseName).*.ps1.bak" |
            Remove-Item -ErrorAction SilentlyContinue
    }

    Context 'Backup file creation' {
        BeforeAll {
            $script:BackupPath = New-StepperBackup -Path $script:OrigPath
        }

        It 'Should return a non-empty path' {
            $script:BackupPath | Should -Not -BeNullOrEmpty
        }

        It 'Should create a file at the returned path' {
            Test-Path -LiteralPath $script:BackupPath | Should -BeTrue
        }

        It 'Should name the backup <BaseName>.<CalVer>.ps1.bak' {
            $backupName = Split-Path -Leaf $script:BackupPath
            # CalVer pattern: yyyy.M.dHHmm  e.g. 2026.5.31430
            $backupName | Should -Match "^$([regex]::Escape($script:BaseName))\.\d{4}\.\d{1,2}\.\d+\.ps1\.bak$"
        }

        It 'Should place the backup in the same directory as the source' {
            $backupDir = Split-Path -Parent $script:BackupPath
            $backupDir | Should -Be (Split-Path -Parent $script:OrigPath)
        }

        It 'Should copy the original content into the backup' {
            Get-Content -LiteralPath $script:BackupPath -Raw | Should -Be $script:OrigContent
        }
    }

    Context 'Does not modify the source file' {
        It 'Should leave the source file unchanged' {
            Get-Content -LiteralPath $script:OrigPath -Raw | Should -Be $script:OrigContent
        }
    }

    Context 'Overwrites an existing backup at the same timestamp' {
        It 'Should overwrite without error when backup already exists' {
            # Call twice; second call should not throw
            New-StepperBackup -Path $script:OrigPath
            { New-StepperBackup -Path $script:OrigPath } | Should -Not -Throw
        }
    }
}
