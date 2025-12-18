function Save-StepData {
    <#
    .SYNOPSIS
        Saves data to disk for use in subsequent steps.

    .DESCRIPTION
        Serializes data to JSON and saves it to a file in the data directory.
        This allows data to persist between steps and survive script restarts.

    .PARAMETER Data
        The data to save. Can be any object that serializes to JSON.

    .PARAMETER Name
        The name for this data file (without extension).

    .PARAMETER DataDirectory
        Optional custom directory for data files. Defaults to .\data relative to the calling script.

    .EXAMPLE
        $users = Get-ADUser -Filter *
        Save-StepData $users "users"

    .EXAMPLE
        Save-StepData $results "results" -DataDirectory "C:\temp\migration-data"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [object]$Data,

        [Parameter(Mandatory, Position = 1)]
        [string]$Name,

        [Parameter(Position = 2)]
        [string]$DataDirectory
    )

    # Determine data directory
    if (-not $DataDirectory) {
        $callStack = Get-PSCallStack
        $callingScript = $callStack[1].ScriptName
        if ($callingScript) {
            $scriptDir = Split-Path -Path $callingScript -Parent
            $DataDirectory = Join-Path -Path $scriptDir -ChildPath "data"
        } else {
            $DataDirectory = ".\data"
        }
    }

    # Ensure directory exists
    if (-not (Test-Path $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }

    # Save data
    $filePath = Join-Path -Path $DataDirectory -ChildPath "$Name.json"
    try {
        $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -ErrorAction Stop
        Write-Verbose "Saved step data to $filePath"
    }
    catch {
        Write-Error "Failed to save step data to ${filePath}: $_"
        throw
    }
}
