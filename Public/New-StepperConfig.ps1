function New-StepperConfig {
    <#
    .SYNOPSIS
        Creates a new JSON configuration file for a Stepper.
    
    .DESCRIPTION
        Generates a JSON configuration file with step definitions.
        Can optionally create the step script files as well.
    
    .PARAMETER Name
        Name of the configuration (without .json extension).
    
    .PARAMETER Path
        Directory where the JSON file will be created.
        Defaults to current directory.
    
    .PARAMETER StepNames
        Array of step names to include in the configuration.
    
    .PARAMETER CreateStepFiles
        If specified, also creates the step script files.
    
    .PARAMETER Force
        Overwrite existing file if it exists.
    
    .EXAMPLE
        New-StepperConfig -Name "My-Script" -StepNames "Step1", "Step2"
        
        Creates My-Script.json with two step definitions.
    
    .EXAMPLE
        New-StepperConfig -Name "Health-Check" -StepNames "DiskSpace", "Services" -CreateStepFiles
        
        Creates config and step files.
    
    .OUTPUTS
        System.IO.FileInfo - The created JSON file.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [string]$Path = (Get-Location).Path,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$StepNames,
        
        [Parameter(Mandatory = $false)]
        [switch]$CreateStepFiles,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting New-StepperConfig for '$Name'"
        
        # Ensure name doesn't have .json extension
        if ($Name -like '*.json') {
            $Name = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        }
        
        # Validate path
        if (-not (Test-Path $Path)) {
            throw "Path does not exist: $Path"
        }
        
        $configPath = Join-Path -Path $Path -ChildPath "$Name.json"
        $stepsDir = Join-Path -Path $Path -ChildPath "Steps"
    }
    
    process {
        try {
            # Check if file exists
            if ((Test-Path $configPath) -and -not $Force) {
                throw "Config file already exists: $configPath. Use -Force to overwrite."
            }
            
            if ($PSCmdlet.ShouldProcess($configPath, "Create Stepper configuration")) {
                # Build step definitions
                $steps = @()
                $order = 1
                
                foreach ($stepName in $StepNames) {
                    $steps += @{
                        name = $stepName
                        description = "Description for $stepName"
                        scriptPath = "Steps/Step-$stepName.ps1"
                        enabled = $true
                        order = $order
                        acceptsAllResults = $false
                    }
                    $order++
                }
                
                # Create config object
                $config = @{
                    StepperSteps = $steps
                }
                
                # Convert to JSON and save
                $json = $config | ConvertTo-Json -Depth 10
                $json | Set-Content -Path $configPath -Encoding UTF8 -Force
                
                Write-Host "Created config: $configPath" -ForegroundColor Green
                
                # Optionally create step files
                if ($CreateStepFiles) {
                    foreach ($stepName in $StepNames) {
                        New-StepperStep -Name $stepName -Path $stepsDir -Force:$Force | Out-Null
                    }
                }
                
                # Return the config file
                Get-Item $configPath
            }
        } catch {
            Write-Error "Failed to create Stepper config: $_"
            throw
        }
    }
    
    end {
        Write-Verbose "Completed New-StepperConfig"
    }
}
