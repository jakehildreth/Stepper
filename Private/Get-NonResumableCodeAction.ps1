function Get-NonResumableCodeAction {
    <#
    .SYNOPSIS
        Prompts user for action on a non-resumable code block.

    .PARAMETER ScriptName
        Name of the script file.

    .PARAMETER ScriptLines
        Array of script lines.

    .PARAMETER Block
        Code block with Lines and IsBeforeStop properties.

    .OUTPUTS
        String with chosen action: 'Wrap', 'Delete', or 'Ignore'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$ScriptLines,

        [Parameter(Mandatory)]
        [hashtable]$Block
    )

    $blockLineNums = $Block.Lines | ForEach-Object { $_ + 1 }  # Convert to 1-based
    $blockCode = $Block.Lines | ForEach-Object { $ScriptLines[$_].Trim() }
    $hasStepperVar = ($blockCode -join ' ') -match '\$Stepper\.'

    Write-Host ""
    Write-Warning "Non-resumable code detected in ${ScriptName}.`nThis code will execute on every run of this script, including resumed runs:"
    foreach ($lineNum in $blockLineNums) {
        $lineContent = $ScriptLines[$lineNum - 1].Trim()
        Write-Host "  ${lineNum}: $lineContent" -ForegroundColor Gray
    }
    Write-Host ""

    if ($hasStepperVar) {
        Write-Warning "This code references `$Stepper variables!"
    }

    Write-Host "How would you like to handle this?" -ForegroundColor Cyan
    Write-Host "  [W] Wrap in New-Step block (Default)" -ForegroundColor Cyan
    if ($hasStepperVar) {
        Write-Host "  [D] Delete this code (WARNING: This will delete code that uses `$Stepper variables)" -ForegroundColor White
    } else {
        Write-Host "  [D] Delete this code" -ForegroundColor White
    }
    Write-Host "  [I] Ignore and continue" -ForegroundColor White
    Write-Host "  [Q] Quit" -ForegroundColor White
    Write-Host ""

    Write-Host "Choice? [" -NoNewline
    Write-Host "W" -NoNewline -ForegroundColor Cyan
    Write-Host "/d/i/q]: " -NoNewline
    $choice = Read-Host

    switch ($choice.ToLower()) {
        'w' { return 'Wrap' }
        '' { return 'Wrap' }  # Default to Wrap
        'd' { return 'Delete' }
        'i' { return 'Ignore' }
        'q' { return 'Quit' }
        default { return 'Wrap' }  # Default to Wrap
    }
}
