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
        # Read the entire script file as a single string
        $content = Get-Content -Path $ScriptPath -Raw -ErrorAction Stop
        
        # Convert the string content to UTF-8 bytes
        # Consistent encoding ensures the hash is reproducible
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        
        # Calculate SHA256 hash of the bytes
        # SHA256 is a cryptographic hash that uniquely identifies file content
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        
        # Convert byte array to hex string (removes dashes for cleaner format)
        # Example: "A1-B2-C3" becomes "A1B2C3"
        [System.BitConverter]::ToString($hash).Replace('-', '')
    }
    catch {
        throw "Failed to calculate hash for script '$ScriptPath': $_"
    }
}
