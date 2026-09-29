BeforeAll {
    # Dot-source the private functions directly for testing
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-StepperConfigPath.ps1"
    . "$ModulePath/Private/Get-StepperConfig.ps1"
}

Describe 'Get-StepperConfigPath' {
    Context 'XDG-compatible path resolution' {
        BeforeEach {
            $script:PrevXdgConfigHome = $env:XDG_CONFIG_HOME
        }

        AfterEach {
            $env:XDG_CONFIG_HOME = $script:PrevXdgConfigHome
        }

        It 'Uses XDG_CONFIG_HOME when set' {
            $env:XDG_CONFIG_HOME = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'C:\xdg' } else { '/tmp/xdg' }
            $result = Get-StepperConfigPath
            $expected = Join-Path -Path (Join-Path -Path $env:XDG_CONFIG_HOME -ChildPath 'stepper') -ChildPath 'config.json'
            $result | Should -Be $expected
        }

        It 'Falls back to a platform default when XDG_CONFIG_HOME is not set' {
            $env:XDG_CONFIG_HOME = $null
            $result = Get-StepperConfigPath
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                $result | Should -Be (Join-Path -Path (Join-Path -Path $env:APPDATA -ChildPath 'stepper') -ChildPath 'config.json')
            } else {
                $result | Should -Be (Join-Path -Path (Join-Path -Path $HOME -ChildPath '.config') -ChildPath 'stepper' | Join-Path -ChildPath 'config.json')
            }
        }

        It 'Falls back when XDG_CONFIG_HOME is whitespace' {
            $env:XDG_CONFIG_HOME = '   '
            $result = Get-StepperConfigPath
            if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                $result | Should -BeLike "$env:APPDATA*"
            } else {
                $result | Should -BeLike "$HOME*"
            }
        }
    }
}

Describe 'Get-StepperConfig' {
    Context 'Config file reading' {
        BeforeEach {
            $script:PrevXdgConfigHome = $env:XDG_CONFIG_HOME
            $script:ConfigHome = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "stepper-config-test-$(New-Guid)"
            $configDir = Join-Path -Path $script:ConfigHome -ChildPath 'stepper'
            $null = New-Item -ItemType Directory -Path $configDir -Force
            $script:ConfigPath = Join-Path -Path $configDir -ChildPath 'config.json'
            $env:XDG_CONFIG_HOME = $script:ConfigHome
        }

        AfterEach {
            $env:XDG_CONFIG_HOME = $script:PrevXdgConfigHome
            if (Test-Path $script:ConfigHome) {
                Remove-Item -Path $script:ConfigHome -Recurse -Force
            }
        }

        It 'Returns an empty object when no config file exists' {
            $result = Get-StepperConfig
            ($null -eq $result) | Should -BeFalse
            @($result.PSObject.Properties).Count | Should -Be 0
        }

        It 'Reads ShowLogo false from the config file' {
            [System.IO.File]::WriteAllText($script:ConfigPath, '{"ShowLogo": false}')
            $result = Get-StepperConfig
            $result.ShowLogo | Should -BeFalse
        }

        It 'Reads ShowLogo true from the config file' {
            [System.IO.File]::WriteAllText($script:ConfigPath, '{"ShowLogo": true}')
            $result = Get-StepperConfig
            $result.ShowLogo | Should -BeTrue
        }

        It 'Warns and returns an empty object for malformed JSON' {
            [System.IO.File]::WriteAllText($script:ConfigPath, '{ not json')
            $result = $null
            Get-StepperConfig -OutVariable result 3>&1 | Should -Not -BeNullOrEmpty
            $result.ShowLogo | Should -BeNullOrEmpty
        }
    }
}
