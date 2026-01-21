function Read-StepperState {
    <#
    .SYNOPSIS
        Reads the Stepper state file.

    .DESCRIPTION
        Reads and deserializes the state file if it exists.
        Returns null if the file doesn't exist or can't be read.

    .PARAMETER StatePath
        The path to the state file.

    .OUTPUTS
        PSCustomObject or $null - The state object containing ScriptHash, ScriptContents, LastCompletedStep, Timestamp, and StepperData
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    # Check if state file exists before trying to read it
    # State file is only created after the first step completes successfully
    if (-not (Test-Path -Path $StatePath)) {
        return $null
    }

    try {
        # Import-Clixml deserializes PowerShell objects saved with Export-Clixml
        # This preserves complex data types like hashtables and custom objects
        # State contains: script hash, last completed step, timestamp, and $Stepper data
        Import-Clixml -Path $StatePath -ErrorAction Stop
    }
    catch {
        # If state file is corrupted or unreadable, warn and return null
        # This allows the script to start fresh instead of failing
        Write-Warning "Failed to read state file '$StatePath': $_"
        return $null
    }
}
