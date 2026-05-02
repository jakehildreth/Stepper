function Get-ShowcaseTemplate {
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

# Example: named step
New-Step 'Step 1: Collect data' {
    # $Stepper.<var> persists values across steps automatically
    $Stepper.ServerName = 'web-01'
    $Stepper.Result     = Invoke-SomeOperation
}

# Example: retry with backoff
New-Step 'Step 2: Deploy' -Retry -RetryInterval 30 -MaxRetries 3 {
    # Reference a value stored in a previous step
    Deploy-App -Server $Stepper.ServerName -Package $Stepper.Result

    # Example: suppress logging for this step
    # New-Step 'Step X: Sensitive operation' -NoLog {
    #     # logging is disabled for this step only
    # }
}

# Example: exclude code from Stepper's unmanaged-code detection
#region Stepper ignore
# Any executable code here is ignored by Stepper's analysis
# $debugVar = 'helper value used outside steps'
#endregion Stepper ignore

Stop-Stepper
'@
}
