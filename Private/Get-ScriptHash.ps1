function Get-ScriptHash {
    <#
    .SYNOPSIS
        Calculates SHA256 hash of a script file.
    
    .DESCRIPTION
        Reads the content of a script file and returns its SHA256 hash.
        Used to detect if the script has been modified since the last run.
    
    .PARAMETER ScriptPath
        The path to the script file.
    
    .OUTPUTS
        System.String - SHA256 hash of the script content
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath
    )
    
    try {
        $content = Get-Content -Path $ScriptPath -Raw -ErrorAction Stop
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        [System.BitConverter]::ToString($hash).Replace('-', '')
    }
    catch {
        throw "Failed to calculate hash for script '$ScriptPath': $_"
    }
}
