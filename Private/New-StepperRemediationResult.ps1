function New-StepperRemediationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Continue', 'Quit', 'Rerun')]
        [string]$Disposition,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$HandledIssues = @(),

        [Parameter()]
        [bool]$Changed = $false,

        [Parameter()]
        [AllowNull()]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [PSCustomObject]@{
        Disposition  = $Disposition
        HandledIssues = @($HandledIssues)
        Changed      = $Changed
        BackupPath   = $BackupPath
        Message      = $Message
    }
}
