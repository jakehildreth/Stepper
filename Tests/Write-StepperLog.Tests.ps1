BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Write-StepperLog.ps1"
}

Describe 'Write-StepperLog' -Tag 'Unit' {
    Context 'Verbose output' {
        It 'Should write a message to the verbose stream' {
            $messages = & {
                $VerbosePreference = 'Continue'
                Write-StepperLog -Message 'test message' 4>&1
            }
            $messages | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                Select-Object -ExpandProperty Message |
                Should -Match 'test message'
        }

        It 'Should include the level in verbose output' {
            $messages = & {
                $VerbosePreference = 'Continue'
                Write-StepperLog -Message 'something failed' -Level 'ERROR' 4>&1
            }
            $messages | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                Select-Object -ExpandProperty Message |
                Should -Match '\[ERROR\]'
        }

        It 'Should default level to INFO' {
            $messages = & {
                $VerbosePreference = 'Continue'
                Write-StepperLog -Message 'default level check' 4>&1
            }
            $messages | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                Select-Object -ExpandProperty Message |
                Should -Match '\[INFO\]'
        }

        It 'Should include a timestamp in the verbose output' {
            $messages = & {
                $VerbosePreference = 'Continue'
                Write-StepperLog -Message 'timestamp check' 4>&1
            }
            $messages | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                Select-Object -ExpandProperty Message |
                Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
        }

        It 'Should include [Stepper] in the verbose output' {
            $messages = & {
                $VerbosePreference = 'Continue'
                Write-StepperLog -Message 'namespace check' 4>&1
            }
            $messages | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } |
                Select-Object -ExpandProperty Message |
                Should -Match '\[Stepper\]'
        }
    }

    Context 'File output — LogPath provided' {
        BeforeEach {
            $LogPath = Join-Path $TestDrive "stepper-$(New-Guid).log"
        }

        It 'Should create a log file at the specified path' {
            Write-StepperLog -Message 'file creation test' -LogPath $LogPath
            $LogPath | Should -Exist
        }

        It 'Should append the message to the log file' {
            Write-StepperLog -Message 'first line' -LogPath $LogPath
            Write-StepperLog -Message 'second line' -LogPath $LogPath
            $content = Get-Content -Path $LogPath
            $content.Count | Should -Be 2
            $content[0] | Should -Match 'first line'
            $content[1] | Should -Match 'second line'
        }

        It 'Should write the level to the log file' {
            Write-StepperLog -Message 'level in file' -Level 'WARN' -LogPath $LogPath
            $content = Get-Content -Path $LogPath -Raw
            $content | Should -Match '\[WARN\]'
        }

        It 'Should write a timestamp to the log file' {
            Write-StepperLog -Message 'ts in file' -LogPath $LogPath
            $content = Get-Content -Path $LogPath -Raw
            $content | Should -Match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'
        }

        It 'Should append to an existing file rather than overwrite it' {
            Add-Content -Path $LogPath -Value 'pre-existing content'
            Write-StepperLog -Message 'appended' -LogPath $LogPath
            $lines = Get-Content -Path $LogPath
            $lines[0] | Should -Be 'pre-existing content'
            $lines[1] | Should -Match 'appended'
        }
    }

    Context 'File output — LogPath not provided' {
        It 'Should not create any file when LogPath is omitted' {
            $dir = $TestDrive
            $before = (Get-ChildItem -Path $dir -Recurse).Count
            Write-StepperLog -Message 'no path'
            $after = (Get-ChildItem -Path $dir -Recurse).Count
            $after | Should -Be $before
        }
    }

    Context 'Unwritable log path' {
        It 'Should emit a warning and not throw when the log path is unwritable' {
            $badPath = Join-Path $TestDrive 'nonexistent-dir' 'stepper.log'
            { Write-StepperLog -Message 'bad path test' -LogPath $badPath -WarningAction SilentlyContinue } |
                Should -Not -Throw
        }

        It 'Should write a warning when the log path is unwritable' {
            $badPath = Join-Path $TestDrive 'nonexistent-dir' 'stepper.log'
            $warnings = Write-StepperLog -Message 'bad path warn' -LogPath $badPath 3>&1
            $warnings | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ValidateSet on Level' {
        It 'Should accept INFO' {
            { Write-StepperLog -Message 'x' -Level 'INFO' } | Should -Not -Throw
        }

        It 'Should accept WARN' {
            { Write-StepperLog -Message 'x' -Level 'WARN' } | Should -Not -Throw
        }

        It 'Should accept ERROR' {
            { Write-StepperLog -Message 'x' -Level 'ERROR' } | Should -Not -Throw
        }

        It 'Should reject an invalid level' {
            { Write-StepperLog -Message 'x' -Level 'DEBUG' } | Should -Throw
        }
    }
}
