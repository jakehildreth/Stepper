function Get-StepperSteps {
    <#
    .SYNOPSIS
        Loads stepper steps from JSON configuration.
    
    .DESCRIPTION
        Reads the stepper-config.json file and dynamically loads
        step scripts from the configured paths. Returns an array of 
        PSCustomObjects with Name, Description, ScriptBlock, and AcceptsAllResults properties.
        
        Steps are loaded from individual .ps1 files in the Steps directory.
        Only enabled steps are included in the returned array.
    
    .PARAMETER ConfigPath
        Path to the configuration JSON file. If not specified, attempts to find a JSON file
        with the same base name as the calling script (e.g., MyScript.ps1 -> MyScript.json).
        Falls back to stepper-config.json in the module root if no match is found.
    
    .OUTPUTS
        PSCustomObject[] - Array of step definition objects with Name, Description, ScriptBlock, and AcceptsAllResults properties.
    
    .EXAMPLE
        $steps = Get-StepperSteps
        
        Automatically finds a JSON config with the same name as the calling script.
        
    .EXAMPLE
        $steps = Get-StepperSteps -ConfigPath "C:\MyProject\custom-config.json"
        
        Uses a specific configuration file.
    
    .NOTES
        Configuration file structure:
        {
          "stepperSteps": [
            {
              "name": "StepName",
              "description": "Step description",
              "scriptPath": "Steps/Step-ScriptName.ps1",
              "enabled": true,
              "order": 1,
              "acceptsAllResults": false
            }
          ]
        }
        
        To add new steps:
        1. Create a new .ps1 file in the Steps directory
        2. Add an entry to stepper-config.json
        3. Set "enabled": true and assign an order number
        
        To disable a step without deleting it:
        - Set "enabled": false in the JSON configuration
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath
    )
    
    Write-Verbose "Loading stepper step configuration"
    
    # Default config path logic
    if (-not $ConfigPath) {
        # Try to find a JSON config with the same name as the calling script
        # Walk the call stack to find the user's script (not a .psm1 module file)
        $callStack = Get-PSCallStack
        $userScript = $null
        
        foreach ($caller in $callStack | Select-Object -Skip 1) {
            $scriptPath = $caller.ScriptName
            if ($scriptPath -and (Test-Path $scriptPath) -and $scriptPath -notlike '*.psm1') {
                $userScript = $scriptPath
                break
            }
        }
        
        if ($userScript) {
            $scriptDirectory = Split-Path -Parent $userScript
            $scriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($userScript)
            $matchingConfig = Join-Path -Path $scriptDirectory -ChildPath "$scriptBaseName.json"
            
            if (Test-Path -Path $matchingConfig) {
                $ConfigPath = $matchingConfig
                Write-Verbose "Auto-discovered config: $ConfigPath"
            } else {
                Write-Verbose "No matching config found at: $matchingConfig"
            }
        }
        
        # Fall back to module root config
        if (-not $ConfigPath) {
            $moduleRoot = Split-Path -Parent $PSScriptRoot
            $ConfigPath = Join-Path -Path $moduleRoot -ChildPath 'stepper-config.json'
            Write-Verbose "Using default module config: $ConfigPath"
        }
    }
    
    # Validate config file exists
    if (-not (Test-Path -Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    
    Write-Verbose "Reading configuration from: $ConfigPath"
    
    # Load and parse JSON configuration
    try {
        $configContent = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $config = $configContent | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Failed to parse configuration file: $_"
    }
    
    # Validate configuration structure
    if (-not $config.stepperSteps) {
        throw "Invalid configuration: 'stepperSteps' property not found"
    }
    
    Write-Verbose "Found $($config.stepperSteps.Count) step(s) in configuration"
    
    # Build step definitions
    $steps = @()
    
    # Sort by order and filter to enabled only
    $enabledSteps = $config.stepperSteps | Where-Object { $_.enabled -eq $true } | Sort-Object -Property order
    
    Write-Verbose "Processing $($enabledSteps.Count) enabled step(s)"
    
    foreach ($stepConfig in $enabledSteps) {
        Write-Verbose "Loading step: $($stepConfig.name)"
        
        # Resolve script path
        # If path is absolute, use it as-is
        # If path is relative, resolve it relative to the config file's directory
        if ([System.IO.Path]::IsPathRooted($stepConfig.scriptPath)) {
            $scriptPath = $stepConfig.scriptPath
        } else {
            $configDirectory = Split-Path -Parent $ConfigPath
            $scriptPath = Join-Path -Path $configDirectory -ChildPath $stepConfig.scriptPath
        }
        
        # Validate script file exists
        if (-not (Test-Path -Path $scriptPath)) {
            Write-Warning "Step script not found: $scriptPath (skipping step '$($stepConfig.name)')"
            continue
        }
        
        Write-Verbose "  Script path: $scriptPath"
        Write-Verbose "  Accepts AllResults: $($stepConfig.acceptsAllResults)"
        
        # Load script content
        try {
            $scriptContent = Get-Content -Path $scriptPath -Raw -ErrorAction Stop
            
            # Create scriptblock
            $scriptBlock = [ScriptBlock]::Create($scriptContent)
            
            # Build step definition as PSCustomObject
            $stepDefinition = [PSCustomObject]@{
                Name = $stepConfig.name
                Description = $stepConfig.description
                ScriptBlock = $scriptBlock
                AcceptsAllResults = $stepConfig.acceptsAllResults
            }
            
            $steps += $stepDefinition
            
            Write-Verbose "  ✓ Successfully loaded step: $($stepConfig.name)"
        } catch {
            Write-Warning "Failed to load step '$($stepConfig.name)': $_"
            continue
        }
    }
    
    Write-Verbose "Successfully loaded $($steps.Count) step(s)"
    
    if ($steps.Count -eq 0) {
        Write-Warning "No enabled steps were loaded from configuration"
    }
    
    return $steps
}
