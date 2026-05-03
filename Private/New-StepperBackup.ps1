function New-StepperBackup {
    <#
    .SYNOPSIS
        Creates a timestamped backup of a script file before Stepper modifies it.

    .DESCRIPTION
        Copies the file at $Path to a backup named
        <BaseName>.<yyyy.M.dHHmm>.ps1.bak in the same directory.
        If a backup with the same timestamp already exists it is overwritten.

    .PARAMETER Path
        The full path to the .ps1 file to back up.

    .OUTPUTS
        [string] The full path of the created backup file.

    .EXAMPLE
        New-StepperBackup -Path 'C:\Scripts\Deploy.ps1'
        # -> C:\Scripts\Deploy.2026.5.31430.ps1.bak
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $resolved) { return }
    $resolvedPath = $resolved.ProviderPath
    $dir          = Split-Path -Parent $resolvedPath
    $baseName     = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)
    $timestamp    = Get-Date -Format 'yyyy.M.dHHmm'
    $backupName   = "$baseName.$timestamp.ps1.bak"
    $backupPath   = Join-Path -Path $dir -ChildPath $backupName

    Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -Force

    return $backupPath
}
