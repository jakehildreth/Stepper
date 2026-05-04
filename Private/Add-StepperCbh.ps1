function Add-StepperCbh {
    <#
    .SYNOPSIS
        Silently injects or updates comment-based help in a Stepper script file.

    .DESCRIPTION
        Inspects the script at ScriptPath for existing comment-based help (CBH).

        - If no CBH exists: inserts a full CBH block (with .SYNOPSIS, .DESCRIPTION,
          and .NOTES containing a Stepper usage blurb) before any existing code.
        - If CBH exists but has no .NOTES section: appends a .NOTES section
          containing the Stepper blurb inside the existing CBH block.
        - If .NOTES already exists: appends the Stepper blurb to it.
        - If the Stepper blurb is already present in .NOTES: makes no changes.

        This function is silent. It never calls Write-Host or exit. It is called
        by Repair-StepperScript as part of the first-run fixup pipeline.

    .PARAMETER ScriptPath
        Absolute path to the PowerShell script file to modify.

    .OUTPUTS
        System.Boolean
        $true if the file was modified, $false if no changes were needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath
    )

    $stepperBlurb = 'Managed by Stepper. Use New-Step blocks to define resumable steps.'

    $content = Get-Content -Path $ScriptPath -Raw
    if (-not $content) {
        $content = ''
    }

    # Detect existing CBH: look for a block comment containing .SYNOPSIS
    $cbhPattern = '(?s)<#.*?\.SYNOPSIS.*?#>'
    $cbhMatch   = [regex]::Match($content, $cbhPattern)

    if (-not $cbhMatch.Success) {
        # No CBH at all... insert a full block at the very top
        $scriptName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
        $newCbh     = @(
            '<#'
            '.SYNOPSIS'
            "    $scriptName"
            ''
            '.DESCRIPTION'
            "    $scriptName"
            ''
            '.NOTES'
            "    $stepperBlurb"
            '#>'
        ) -join [System.Environment]::NewLine
        $newContent = $newCbh + [System.Environment]::NewLine + $content
        New-StepperBackup -Path $ScriptPath | Out-Null
        Set-Content -Path $ScriptPath -Value $newContent -Encoding UTF8 -NoNewline
        return $true
    }

    $cbhText  = $cbhMatch.Value
    $cbhStart = $cbhMatch.Index

    # Check if Stepper blurb is already there
    if ($cbhText -match [regex]::Escape($stepperBlurb)) {
        return $false
    }

    # CBH exists... does it have a .NOTES section?
    $notesPattern = '(?s)(\.NOTES\s*\r?\n)(.*?)(\r?\n\s*(?:\.[A-Z]|#>))'
    $notesMatch   = [regex]::Match($cbhText, $notesPattern)

    if ($notesMatch.Success) {
        # .NOTES exists... append blurb inside it
        $insertion = $notesMatch.Groups[1].Value +
                     $notesMatch.Groups[2].Value +
                     [System.Environment]::NewLine + "    $stepperBlurb" +
                     $notesMatch.Groups[3].Value
        $newCbhText = $cbhText.Remove($notesMatch.Index, $notesMatch.Length).Insert(
            $notesMatch.Index, $insertion
        )
    } else {
        # No .NOTES... insert one before closing #>
        $closeIdx  = $cbhText.LastIndexOf('#>')
        $notesBlock = [System.Environment]::NewLine + ".NOTES" +
                      [System.Environment]::NewLine + "    $stepperBlurb" +
                      [System.Environment]::NewLine
        $newCbhText = $cbhText.Insert($closeIdx, $notesBlock)
    }

    $newContent = $content.Remove($cbhStart, $cbhMatch.Length).Insert($cbhStart, $newCbhText)
    New-StepperBackup -Path $ScriptPath | Out-Null
    Set-Content -Path $ScriptPath -Value $newContent -Encoding UTF8 -NoNewline
    return $true
}
