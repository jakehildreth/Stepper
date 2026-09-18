function New-StepperBackup {
    <#
    .SYNOPSIS
        Creates a timestamped backup of a script file before Stepper modifies it.

    .DESCRIPTION
        Copies the file at $Path to a backup named
        <BaseName>.<yyyy.M.dHHmmssfff>.ps1.bak in the same directory.
        If that name already exists, a numeric collision suffix is added.

    .PARAMETER Path
        The full path to the .ps1 file to back up.

    .OUTPUTS
        [string] The full path of the created backup file.

    .EXAMPLE
        New-StepperBackup -Path 'C:\Scripts\Deploy.ps1'
        # -> C:\Scripts\Deploy.2026.5.3143015123.ps1.bak
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
    $timestamp    = Get-Date -Format 'yyyy.M.dHHmmssfff'
    $backupName   = "$baseName.$timestamp.ps1.bak"
    $backupPath   = Join-Path -Path $dir -ChildPath $backupName
    $suffix = 1
    while (Test-Path -LiteralPath $backupPath) {
        $backupName = "$baseName.$timestamp.$suffix.ps1.bak"
        $backupPath = Join-Path -Path $dir -ChildPath $backupName
        $suffix++
    }

    Copy-Item -LiteralPath $resolvedPath -Destination $backupPath -ErrorAction Stop

    return $backupPath
}
