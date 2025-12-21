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

    if (-not (Test-Path -Path $StatePath)) {
        return $null
    }

    try {
        Import-Clixml -Path $StatePath -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to read state file '$StatePath': $_"
        return $null
    }
}
