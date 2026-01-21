function Write-StepperState {
    <#
    .SYNOPSIS
        Writes the Stepper state file.

    .DESCRIPTION
        Serializes and writes the state object to disk.

    .PARAMETER StatePath
        The path to the state file.

    .PARAMETER ScriptHash
        SHA256 hash of the script content.

    .PARAMETER LastCompletedStep
        Identifier of the last successfully completed step (format: "filepath:line").

    .PARAMETER StepperData
        The $Stepper hashtable to persist.

    .PARAMETER ScriptContents
        The full contents of the script at the time of saving (string). Useful for inspection when the script changes.

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath,

        [Parameter(Mandatory)]
        [string]$ScriptHash,

        [Parameter(Mandatory)]
        [string]$LastCompletedStep,

        [Parameter()]
        [hashtable]$StepperData,

        [Parameter()]
        [string]$ScriptContents
    )

    # Create a custom object to hold all state information
    # This will be serialized to disk and restored on resume
    $state = [PSCustomObject]@{
        ScriptHash        = $ScriptHash        # Detects script modifications
        ScriptContents    = $ScriptContents    # Full script text for change inspection
        LastCompletedStep = $LastCompletedStep # Where to resume from (format: "path:line")
        Timestamp         = (Get-Date).ToString('o') # ISO 8601 format timestamp
        StepperData       = $StepperData       # User's $Stepper variables to restore
    }

    try {
        # Export-Clixml serializes PowerShell objects to XML format
        # This preserves data types (hashtables, arrays, etc.) unlike JSON
        # The state file allows resuming execution from the last completed step
        Export-Clixml -Path $StatePath -InputObject $state -ErrorAction Stop
    }
    catch {
        # Warn but don't fail - state persistence is helpful but not critical
        Write-Warning "Failed to write state file '$StatePath': $_"
    }
}
