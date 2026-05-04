function New-StepperScript {
    <#
    .SYNOPSIS
        Creates a new PowerShell script pre-wired for the Stepper module.

    .DESCRIPTION
        Generates a .ps1 file containing the minimum required structure for a Stepper
        script: comment-based help, [CmdletBinding()] param(), an Install-Module guard,
        two placeholder New-Step blocks, and Stop-Stepper.

        Use -Showcase (aliases: -Full, -Detailed, -WithExamples) to include additional
        commented examples demonstrating $Stepper.<var> persistence, named steps,
        -NoLog, -Retry, and #region Stepper ignore blocks.

        Both templates pass Test-StepperScript with IsValid = $true out of the box.

        Use -Path for a full file path, or -Name + -Directory to specify name and
        location separately (-Directory defaults to the current working directory).

    .PARAMETER Path
        Full path to the .ps1 file to create.

    .PARAMETER Name
        Name of the script (without extension). The file is written as <Name>.ps1.

    .PARAMETER Directory
        Directory in which to create the script when using -Name. Defaults to $PWD.

    .PARAMETER Force
        Overwrite the target file if it already exists.

    .PARAMETER Showcase
        Generate the full feature-showcase template instead of the minimal skeleton.

    .OUTPUTS
        System.IO.FileInfo: the created file, suitable for pipeline use.

    .EXAMPLE
        New-StepperScript -Path './Deploy.ps1'

    .EXAMPLE
        New-StepperScript -Name 'Deploy' -Directory './scripts' -Showcase
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPath', SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPath', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByName')]
        [string]$Directory = $PWD,

        [switch]$Force,

        [Alias('Full', 'Detailed', 'WithExamples')]
        [switch]$Showcase
    )

    # Resolve target path
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $Path = Join-Path $Directory "$Name.ps1"
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if ((Test-Path -LiteralPath $resolvedPath) -and -not $Force) {
        $PSCmdlet.WriteError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.IOException]::new("File already exists: $resolvedPath. Use -Force to overwrite."),
                'FileAlreadyExists',
                [System.Management.Automation.ErrorCategory]::ResourceExists,
                $resolvedPath
            )
        )
        return
    }

    $content = if ($Showcase) { Get-ShowcaseTemplate } else { Get-MinimalTemplate }

    if ($PSCmdlet.ShouldProcess($resolvedPath, 'Create Stepper script')) {
        $dir = Split-Path -Path $resolvedPath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $content | Set-Content -Path $resolvedPath -Encoding UTF8 -NoNewline
        Get-Item -LiteralPath $resolvedPath
    }
}
