function New-StepperIssue {
    <#
    .SYNOPSIS
        Creates a structured issue object for Test-StepperScript results.

    .PARAMETER Code
        Machine-readable issue code (e.g. 'MissingCmdletBinding').

    .PARAMETER Severity
        Issue severity: 'Error' or 'Warning'.

    .PARAMETER Message
        Human-readable description of the issue and how to resolve it.

    .OUTPUTS
        PSCustomObject with properties: Code, Severity, Message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [PSCustomObject]@{
        Code     = $Code
        Severity = $Severity
        Message  = $Message
    }
}
