function Get-MinimalTemplate {
    return @'
<#
.SYNOPSIS
    Brief description of what this script does.

.DESCRIPTION
    Detailed description of this script.

.NOTES
    This script uses the Stepper module to enable resumable execution.
    See https://github.com/jakehildreth/Stepper for more information.
#>
[CmdletBinding()]
param()

#region Stepper ignore
if (-not (Get-Module -Name Stepper) -and -not (Get-Module -ListAvailable -Name Stepper)) { Install-Module Stepper -Force }
#endregion Stepper ignore

New-Step {
    # Step 1: Describe what this step does
}

New-Step {
    # Step 2: Describe what this step does
}

Stop-Stepper
'@
}
