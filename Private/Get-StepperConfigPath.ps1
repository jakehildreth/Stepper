function Get-StepperConfigPath {
    <#
    .SYNOPSIS
        Gets the path to the Stepper configuration file.

    .DESCRIPTION
        Returns the path to the Stepper configuration file (config.json) in an
        XDG Base Directory compatible location:
        - $env:XDG_CONFIG_HOME/stepper/config.json when XDG_CONFIG_HOME is set
        - $env:APPDATA/stepper/config.json on Windows when XDG_CONFIG_HOME is not set
        - ~/.config/stepper/config.json on Linux/macOS when XDG_CONFIG_HOME is not set

    .OUTPUTS
        System.String - Path to the configuration file
    #>
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:XDG_CONFIG_HOME)) {
        $configHome = $env:XDG_CONFIG_HOME
    } elseif ($env:OS -eq 'Windows_NT') {
        $configHome = $env:APPDATA
    } else {
        $configHome = Join-Path -Path $HOME -ChildPath '.config'
    }

    Join-Path -Path (Join-Path -Path $configHome -ChildPath 'stepper') -ChildPath 'config.json'
}
