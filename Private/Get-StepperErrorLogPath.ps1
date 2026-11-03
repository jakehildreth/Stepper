function Get-StepperErrorLogPath {
    <#
    .SYNOPSIS
        Derives the error log path from the Stepper log path.

    .DESCRIPTION
        Inserts '.errors' before the extension of the log path, so
        script.ps1.stepper.log becomes script.ps1.stepper.errors.log. A log path
        without an extension gets '.errors.log' appended. Returns $null when no
        log path is given.

    .PARAMETER LogPath
        The resolved Stepper log path.

    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$LogPath
    )

    if ([string]::IsNullOrEmpty($LogPath)) {
        return $null
    }

    $directory = [System.IO.Path]::GetDirectoryName($LogPath)
    $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($LogPath)
    $extension = [System.IO.Path]::GetExtension($LogPath)
    if (-not $extension) {
        $extension = '.log'
    }

    $errorFileName = "$baseName.errors$extension"
    if ($directory) {
        Join-Path -Path $directory -ChildPath $errorFileName
    } else {
        $errorFileName
    }
}
