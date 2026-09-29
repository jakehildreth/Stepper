function New-StepperIssue {
    <#
    .SYNOPSIS
        Creates a canonical Test-StepperScript finding.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter()]
        [ValidateSet('Error', 'Warning')]
        [string]$Severity,

        [Parameter()]
        [string]$Message,

        [Parameter()]
        [System.Management.Automation.Language.IScriptExtent]$Extent,

        [Parameter()]
        [PSCustomObject]$Location
    )

    $definition = (Get-StepperFindingCatalog)[$Code]
    if (-not $definition) {
        throw "Unknown Stepper finding code '$Code'."
    }

    if (-not $PSBoundParameters.ContainsKey('Severity')) { $Severity = $definition.Severity }
    if (-not $PSBoundParameters.ContainsKey('Message')) { $Message = $definition.Message }

    if ($Extent) {
        $Location = [PSCustomObject]@{
            StartLine   = $Extent.StartLineNumber
            StartColumn = $Extent.StartColumnNumber
            EndLine     = $Extent.EndLineNumber
            EndColumn   = $Extent.EndColumnNumber
            Text        = $Extent.Text
        }
    }

    [PSCustomObject]@{
        Code        = $Code
        Severity    = $Severity
        Message     = $Message
        Location    = $Location
        Remediation = $definition.Remediation
    }
}
