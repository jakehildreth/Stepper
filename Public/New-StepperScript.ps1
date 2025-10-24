function New-StepperScript {
    <#
    .SYNOPSIS
        Creates a new Stepper script with configuration and step files.
    
    .DESCRIPTION
        Scaffolds a complete Stepper script structure including:
        - Main script file
        - JSON configuration file
        - Steps directory
        - Optional example step files
    
    .PARAMETER Name
        Name of the Stepper script (e.g., "My-HealthCheck").
        The .ps1 extension will be added automatically.
    
    .PARAMETER Path
        Directory where the Stepper script will be created.
        Defaults to current directory.
    
    .PARAMETER StepNames
        Array of step names to create as examples.
        If not specified, creates one example step.
    
    .PARAMETER Force
        Overwrite existing files if they exist.
    
    .EXAMPLE
        New-StepperScript -Name "My-HealthCheck"
        
        Creates a new Stepper script in the current directory with one example step.
    
    .EXAMPLE
        New-StepperScript -Name "Security-Assessment" -Path "C:\Scripts" -StepNames "Scan", "Analyze", "Report"
        
        Creates a security assessment Stepper with three steps.
    
    .OUTPUTS
        System.IO.FileInfo - The created script file.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path,
        
        [Parameter(Mandatory = $false)]
        [string[]]$StepNames = @('ExampleStep'),
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting New-StepperScript for '$Name'"
        
        # Ensure name doesn't have .ps1 extension
        if ($Name -like '*.ps1') {
            $Name = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        }
        
        # Validate path
        if (-not (Test-Path $Path)) {
            throw "Path does not exist: $Path"
        }
        
        $scriptPath = Join-Path -Path $Path -ChildPath "$Name.ps1"
        $configPath = Join-Path -Path $Path -ChildPath "$Name.json"
        $stepsDir = Join-Path -Path $Path -ChildPath "Steps"
    }
    
    process {
        try {
            # Check if files exist
            if ((Test-Path $scriptPath) -and -not $Force) {
                throw "Script file already exists: $scriptPath. Use -Force to overwrite."
            }
            
            if ((Test-Path $configPath) -and -not $Force) {
                throw "Config file already exists: $configPath. Use -Force to overwrite."
            }
            
            if ($PSCmdlet.ShouldProcess($scriptPath, "Create Stepper script")) {
                # Create Steps directory
                if (-not (Test-Path $stepsDir)) {
                    New-Item -Path $stepsDir -ItemType Directory -Force | Out-Null
                    Write-Verbose "Created Steps directory: $stepsDir"
                }
                
                # Create main script
                $scriptContent = @"
<#
.SYNOPSIS
    $Name Stepper script.

.DESCRIPTION
    Multi-step Stepper script using the Stepper module.
    State is automatically saved and can be resumed if interrupted.

.PARAMETER Fresh
    Start fresh, ignoring any saved state.

.PARAMETER ShowStatus
    Display current progress without running steps.

.PARAMETER Reset
    Reset all saved progress.

.EXAMPLE
    .\$Name.ps1
    
    Run the Stepper (resumes automatically if interrupted).

.EXAMPLE
    .\$Name.ps1 -Fresh
    
    Start fresh, ignoring any saved state.

.NOTES
    Requires: Stepper module
    Configuration: $Name.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = `$false)]
    [switch]`$Fresh,
    
    [Parameter(Mandatory = `$false)]
    [switch]`$ShowStatus,
    
    [Parameter(Mandatory = `$false)]
    [switch]`$Reset
)

# Import Stepper module
if (-not (Get-Module -Name Stepper -ListAvailable)) {
    Write-Error "Stepper module is not installed. Install it with: Install-Module Stepper"
    return
}

Import-Module Stepper -Force

# Handle ShowStatus
if (`$ShowStatus) {
    Show-StepperStatus
    return
}

# Handle Reset
if (`$Reset) {
    Reset-StepperState
    return
}

# Note: Get-StepperSteps will automatically find $Name.json
# in the same directory as this script

# Run the Stepper using Stepper module
try {
    if (`$Fresh) {
        Start-Stepper -Fresh
    } else {
        Start-Stepper
    }
} catch {
    Write-Error "Stepper failed: `$_"
    return
}

Write-Host ""
Write-Host "Stepper complete! Review the results above." -ForegroundColor Green
Write-Host ""
"@
                
                $scriptContent | Set-Content -Path $scriptPath -Encoding UTF8 -Force
                Write-Host "Created script: $scriptPath" -ForegroundColor Green
                
                # Create JSON config using New-StepperConfig
                New-StepperConfig -Name $Name -Path $Path -StepNames $StepNames -Force:$Force | Out-Null
                
                # Return the script file
                Get-Item $scriptPath
            }
        } catch {
            Write-Error "Failed to create Stepper script: $_"
            throw
        }
    }
    
    end {
        Write-Verbose "Completed New-StepperScript"
    }
}
