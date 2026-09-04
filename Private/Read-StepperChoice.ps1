function Read-StepperChoice {
    <#
    .SYNOPSIS
        Reads a single user menu choice, with a test hook and a non-interactive default.

    .DESCRIPTION
        Thin wrapper around Read-Host used by every Stepper menu prompt. It exists
        so tests can drive menu choices without a console, and so non-interactive
        runs take a documented default instead of hanging.

        Resolution order:
          1. If the script-scope variable __StepperTestResponses is a non-empty
             queue (System.Collections.Generic.Queue[string]), dequeue and return
             the next response. Tests populate this before invoking a cmdlet.
          2. Try Read-Host and return whatever the user types.
          3. If Read-Host throws (non-interactive host), return -NonInteractiveDefault.

    .PARAMETER NonInteractiveDefault
        The choice returned when no test response is queued and Read-Host is
        unavailable. Callers pick the safe default for their menu (for example
        's' for Start Over, 'r' for Resume, 'c' for Continue).

    .OUTPUTS
        System.String. The raw choice text (may be empty when the user pressed Enter).

    .NOTES
        Private helper. Not exported. The __StepperTestResponses hook is a testing
        back door; it is never set by production code.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$NonInteractiveDefault = ''
    )

    # Test hook: a queued response short-circuits all host interaction.
    $queue = Get-Variable -Name '__StepperTestResponses' -Scope Script -ErrorAction SilentlyContinue
    if ($queue -and $queue.Value -is [System.Collections.Generic.Queue[string]] -and $queue.Value.Count -gt 0) {
        return $queue.Value.Dequeue()
    }

    try {
        return Read-Host
    }
    catch {
        Write-Verbose "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][Stepper] Non-interactive context detected, defaulting to '$NonInteractiveDefault'"
        return $NonInteractiveDefault
    }
}
