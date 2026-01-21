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
    
    # Extract the directory where the script is located
    $scriptDir = Split-Path -Path $ScriptPath -Parent
    
    # Extract just the filename (e.g., "deploy.ps1")
    $scriptName = Split-Path -Path $ScriptPath -Leaf
    
    # Create state filename by appending .stepper extension
    # Example: "deploy.ps1" becomes "deploy.ps1.stepper"
    # Kept in same directory as script for easy discovery
    $stateFileName = "$scriptName.stepper"
    
    # Combine directory and filename to get full path
    Join-Path -Path $scriptDir -ChildPath $stateFileName
}
