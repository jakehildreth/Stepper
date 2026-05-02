BeforeAll {
    $ModulePath = Split-Path -Path $PSScriptRoot -Parent
    . "$ModulePath/Private/Get-ScriptHash.ps1"
    . "$ModulePath/Private/Get-ScriptAst.ps1"
    . "$ModulePath/Private/Find-NewStepBlocks.ps1"
    . "$ModulePath/Private/Add-StepperCbh.ps1"
    . "$ModulePath/Private/Get-MinimalTemplate.ps1"
    . "$ModulePath/Private/Get-ShowcaseTemplate.ps1"
    . "$ModulePath/Public/Test-StepperScript.ps1"
    . "$ModulePath/Public/New-StepperScript.ps1"
}

Describe 'New-StepperScript' -Tag 'Unit' {

    Context 'ByPath parameter set' {
        It 'Creates a file at the specified path' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                # Assert
                $path | Should -Exist
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Returns a FileInfo object pointing to the created file' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                $result = New-StepperScript -Path $path
                # Assert
                $result | Should -BeOfType [System.IO.FileInfo]
                $result.FullName | Should -Be $path
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Errors if file already exists and -Force not specified' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            'existing content' | Set-Content -Path $path
            try {
                # Act / Assert
                { New-StepperScript -Path $path -ErrorAction Stop } | Should -Throw
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Overwrites existing file when -Force is specified' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            'existing content' | Set-Content -Path $path
            try {
                # Act
                New-StepperScript -Path $path -Force | Out-Null
                # Assert
                $content = Get-Content -Path $path -Raw
                $content | Should -Not -Match 'existing content'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'ByName parameter set' {
        It 'Creates a .ps1 file named <Name>.ps1 in the specified directory' {
            # Arrange
            $dir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $dir | Out-Null
            try {
                # Act
                New-StepperScript -Name 'Deploy' -Directory $dir | Out-Null
                # Assert
                (Join-Path $dir 'Deploy.ps1') | Should -Exist
            }
            finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        It 'Defaults to $PWD when -Directory is omitted' {
            # Arrange
            $savedPwd = $PWD
            $dir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Location $dir
            try {
                # Act
                New-StepperScript -Name 'MyScript' | Out-Null
                # Assert
                (Join-Path $dir 'MyScript.ps1') | Should -Exist
            }
            finally {
                Set-Location $savedPwd
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Returns a FileInfo object with the constructed path' {
            # Arrange
            $dir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid())
            New-Item -ItemType Directory -Path $dir | Out-Null
            $expectedPath = Join-Path $dir 'Deploy.ps1'
            try {
                # Act
                $result = New-StepperScript -Name 'Deploy' -Directory $dir
                # Assert
                $result | Should -BeOfType [System.IO.FileInfo]
                $result.FullName | Should -Be $expectedPath
            }
            finally { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'Minimal template (default)' {
        It 'Passes Test-StepperScript with IsValid = $true' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeTrue
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains [CmdletBinding()] param()' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '\[CmdletBinding\(\)\]'
                $content | Should -Match 'param\(\)'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains Install-Module Stepper guard' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match 'Install-Module\s+Stepper'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains at least two New-Step blocks' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                ([regex]::Matches($content, 'New-Step\s*\{')).Count | Should -BeGreaterOrEqual 2
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains Stop-Stepper' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match 'Stop-Stepper'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains comment-based help' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
                # Assert
                $ast.GetHelpContent() | Should -Not -BeNullOrEmpty
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Does NOT contain $Stepper. variable references (minimal only)' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert — showcase-only content should not appear in minimal
                $content | Should -Not -Match '\$Stepper\.'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }

    Context 'Showcase template (-Showcase)' {
        It 'Passes Test-StepperScript with IsValid = $true' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -Showcase | Out-Null
                $result = Test-StepperScript -ScriptPath $path
                # Assert
                $result.IsValid | Should -BeTrue
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains $Stepper. variable usage examples' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -Showcase | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '\$Stepper\.'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains #region Stepper ignore example' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -Showcase | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '#region Stepper ignore'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Contains -Retry usage example' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -Showcase | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '-Retry'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Accepts -Full alias for -Showcase' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -Full | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '\$Stepper\.'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }

        It 'Accepts -WithExamples alias for -Showcase' {
            # Arrange
            $path = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$([System.Guid]::NewGuid()).ps1")
            try {
                # Act
                New-StepperScript -Path $path -WithExamples | Out-Null
                $content = Get-Content -Path $path -Raw
                # Assert
                $content | Should -Match '\$Stepper\.'
            }
            finally { Remove-Item $path -ErrorAction SilentlyContinue }
        }
    }
}
