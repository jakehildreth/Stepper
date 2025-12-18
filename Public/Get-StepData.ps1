function Get-StepData {
    <#
    .SYNOPSIS
        Retrieves data saved by a previous step.

    .DESCRIPTION
        Loads and deserializes JSON data from a file in the data directory.
        Returns $null if the file doesn't exist.

    .PARAMETER Name
        The name of the data file to load (without extension).

    .PARAMETER DataDirectory
        Optional custom directory for data files. Defaults to .\data relative to the calling script.

    .PARAMETER Required
        If specified, throws an error if the data file doesn't exist.
        Useful for catching missing dependencies early.

    .EXAMPLE
        $users = Get-StepData "users"
        if ($users) {
            Process-Users $users
        }

    .EXAMPLE
        $results = Get-StepData "results" -Required

    .EXAMPLE
        $data = Get-StepData "export" -DataDirectory "C:\temp\migration-data"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$DataDirectory,

        [switch]$Required
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

    $filePath = Join-Path -Path $DataDirectory -ChildPath "$Name.json"

    if (-not (Test-Path $filePath)) {
        if ($Required) {
            throw "Required step data file not found: $filePath"
        }
        Write-Verbose "Step data file not found: $filePath"
        return $null
    }

    try {
        $data = Get-Content -Path $filePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        Write-Verbose "Loaded step data from $filePath"
        return $data
    }
    catch {
        Write-Error "Failed to load step data from ${filePath}: $_"
        throw
    }
}
