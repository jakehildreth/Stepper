function Get-StateFilePath {
    <#
    .SYNOPSIS
        Returns the path to the state file.
    
    .DESCRIPTION
        Returns the full path to the Stepper state file, creating the
        directory if it doesn't exist.
    
    .PARAMETER FileName
        The name of the state file. Default is 'stepper-state.json'.
    
    .OUTPUTS
        System.String - The full path to the state file.
    
    .EXAMPLE
        $statePath = Get-StateFilePath
        
        Gets the default state file path.
    
    .EXAMPLE
        $statePath = Get-StateFilePath -FileName 'custom-state.json'
        
        Gets a custom state file path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$FileName = 'stepper-state.json'
    )
    
    # Store in user profile for persistence across sessions
    # Alternative: Use temp folder for session-only persistence
    # Cross-platform home directory detection
    $homeDir = if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
        $env:USERPROFILE
    } else {
        $env:HOME
    }
    
    $stateDir = Join-Path -Path $homeDir -ChildPath '.stepper'
    
    if (-not (Test-Path $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
        Write-Verbose "Created state directory: $stateDir"
    }
    
    $statePath = Join-Path -Path $stateDir -ChildPath $FileName
    Write-Verbose "State file path: $statePath"
    
    return $statePath
}
