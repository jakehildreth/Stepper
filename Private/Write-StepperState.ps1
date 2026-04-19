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

    .PARAMETER StepName
        Optional name of the completed step.

    .PARAMETER StepNumber
        1-based index of the completed step.

    .PARAMETER StepperData
        The $Stepper hashtable to persist.

    .PARAMETER ScriptContents
        The full contents of the script at the time of saving (string). Useful for inspection when the script changes.

    .PARAMETER LogPath
        Resolved path to the Stepper log file for this run. Persisted so resumed runs use the same path.

    .PARAMETER LoggingEnabled
        Whether logging is enabled for this run. Persisted so resumed runs respect the user's choice.

    .PARAMETER NoLogStepIds
        Step identifiers (ScriptPath:LineNumber) for steps with -NoLog. Persisted alongside LoggingEnabled.

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
        [string]$StepName,

        [Parameter()]
        [int]$StepNumber,

        [Parameter()]
        [hashtable]$StepperData,

        [Parameter()]
        [string]$ScriptContents,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [bool]$LoggingEnabled,

        [Parameter()]
        [string[]]$NoLogStepIds
    )

    $state = [PSCustomObject]@{
        ScriptHash              = $ScriptHash
        ScriptContents          = $ScriptContents
        LastCompletedStep       = $LastCompletedStep
        LastCompletedStepName   = $StepName
        LastCompletedStepNumber = $StepNumber
        Timestamp               = (Get-Date).ToString('o')
        StepperData             = $StepperData
        LogPath                 = $LogPath
        LoggingEnabled          = $LoggingEnabled
        NoLogStepIds            = $NoLogStepIds
    }

    try {
        Export-Clixml -Path $StatePath -InputObject $state -ErrorAction Stop
    }
    catch {
        $exception = [System.IO.IOException]::new("Failed to write state file '$StatePath'", $_.Exception)
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'StateWriteFailed',
            [System.Management.Automation.ErrorCategory]::WriteError,
            $StatePath
        )
        $PSCmdlet.WriteError($errorRecord)
    }
}
