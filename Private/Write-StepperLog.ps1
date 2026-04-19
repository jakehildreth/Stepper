function Write-StepperLog {
    <#
    .SYNOPSIS
        Writes a structured log entry to the verbose stream and optionally to a log file.

    .DESCRIPTION
        Centralizes all Stepper log output. Always emits a timestamped, levelled line to
        Write-Verbose. When -LogPath is provided, appends the same line to that file using
        Add-Content (append mode). File write failures emit a non-terminating Write-Warning
        and never throw.

    .PARAMETER Message
        The message to log.

    .PARAMETER Level
        Log level: INFO, WARN, or ERROR. Defaults to INFO.

    .PARAMETER LogPath
        Optional path to a log file. If omitted, output is verbose-only.

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$LogPath
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp][$Level][Stepper] $Message"

    Write-Verbose $line

    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $line -ErrorAction Stop
        } catch {
            Write-Warning "Stepper could not write to log file '$LogPath': $_"
        }
    }
}
