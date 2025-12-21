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

    $state = [PSCustomObject]@{
        ScriptHash        = $ScriptHash
        ScriptContents    = $ScriptContents
        LastCompletedStep = $LastCompletedStep
        Timestamp         = (Get-Date).ToString('o')
        StepperData       = $StepperData
    }

    try {
        Export-Clixml -Path $StatePath -InputObject $state -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write state file '$StatePath': $_"
    }
}
