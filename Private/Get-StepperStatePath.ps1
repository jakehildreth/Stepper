function Get-StepperStatePath {
    <#
    .SYNOPSIS
        Gets the path to the Stepper state file for the calling script.
    
    .DESCRIPTION
        Generates a state file path based on the calling script's location.
        State files are stored in the same directory as the script with a .stepper extension.
    
    .PARAMETER ScriptPath
        The path to the script file.
    
    .OUTPUTS
        System.String - Path to the state file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )
    
    $scriptDir = Split-Path -Path $ScriptPath -Parent
    $scriptName = Split-Path -Path $ScriptPath -Leaf
    $stateFileName = "$scriptName.stepper"
    
    Join-Path -Path $scriptDir -ChildPath $stateFileName
}
