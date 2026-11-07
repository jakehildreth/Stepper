function Write-StepperErrorLog {
    <#
    .SYNOPSIS
        Appends full non-terminating error details for a step to the error log.

    .DESCRIPTION
        Writes a step header followed by the message, fully qualified error id,
        category, target, position, and script stack trace of each record. File
        write failures emit a Write-Warning and never throw.

    .PARAMETER ErrorRecord
        The error records captured while the step ran.

    .PARAMETER LogPath
        The error log path.

    .PARAMETER StepLabel
        Text that identifies the step, for example "Step 2/5 - 'Deploy'".

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$ErrorRecord,

        [Parameter(Mandatory)]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [string]$StepLabel
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("=== [$timestamp] $StepLabel : $($ErrorRecord.Count) non-terminating error(s) ===")

    $index = 0
    foreach ($record in $ErrorRecord) {
        $index++
        $lines.Add("--- Error $index ---")
        $lines.Add("Message  : $($record.Exception.Message)")
        $lines.Add("ErrorId  : $($record.FullyQualifiedErrorId)")
        $lines.Add("Category : $($record.CategoryInfo)")
        if ($null -ne $record.TargetObject) {
            $lines.Add("Target   : $($record.TargetObject)")
        }
        if ($record.InvocationInfo -and $record.InvocationInfo.PositionMessage) {
            $lines.Add("Position : $($record.InvocationInfo.PositionMessage.Trim())")
        }
        if ($record.ScriptStackTrace) {
            $lines.Add("Stack    : $($record.ScriptStackTrace)")
        }
    }
    $lines.Add("=== END $StepLabel ===")

    try {
        Add-Content -Path $LogPath -Value $lines -ErrorAction Stop
    } catch {
        Write-Warning "Stepper could not write to error log '$LogPath': $_"
    }
}
