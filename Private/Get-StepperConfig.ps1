function Get-StepperConfig {
    <#
    .SYNOPSIS
        Reads the Stepper configuration file.

    .DESCRIPTION
        Reads the Stepper configuration file (config.json) from the XDG-compatible
        location returned by Get-StepperConfigPath. Returns an empty object when no
        configuration file exists. Warns and returns an empty object when the file
        cannot be parsed.

        Supported settings:
        - ShowLogo (bool): set to false to suppress the splash screen on module import.

    .OUTPUTS
        PSCustomObject - The parsed configuration, or an empty object
    #>
    [CmdletBinding()]
    param()

    $configPath = Get-StepperConfigPath
    if (Test-Path -Path $configPath) {
        try {
            return Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Warning "Unable to parse Stepper config at '$configPath': $_"
        }
    }

    [pscustomobject]@{}
}
