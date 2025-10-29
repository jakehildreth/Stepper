function New-StepperConfig {
    <#
    .SYNOPSIS
        Creates a new JSON configuration file for a Stepper.
    
    .DESCRIPTION
        Generates a JSON configuration file with step definitions.
        Creates the step script files by default.
    
    .PARAMETER Name
        Name of the configuration (without .json extension).
    
    .PARAMETER Path
        Directory where the JSON file will be created.
        Defaults to current directory.
    
    .PARAMETER StepNames
        Array of step names to include in the configuration.
    
    .PARAMETER SkipStepFiles
        If specified, does not create the step script files.
    
    .PARAMETER Force
        Overwrite existing files if they exist.
    
    .EXAMPLE
        New-StepperConfig -Name "My-Script" -StepNames "Step1", "Step2"
        
        Creates My-Script.json with two step definitions and creates the step files.
    
    .EXAMPLE
        New-StepperConfig -Name "Health-Check" -StepNames "DiskSpace", "Services" -SkipStepFiles
        
        Creates config only, without step files.
    
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
        [switch]$SkipStepFiles,
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    begin {
        Write-Verbose "Starting New-StepperConfig for '$Name'"
        
        # Ensure name doesn't have .json extension
        if ($Name -like '*.json') {
            $Name = [System.IO.Path]::GetFileNameWithoutExtension($Name)
        }
        
        # Validate path and offer to create if it doesn't exist
        if (-not (Test-Path $Path)) {
            $title = "Directory Does Not Exist"
            $message = "Path does not exist: $Path`nCreate directory?"
            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Create the directory"
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Cancel operation"
            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
            $choice = $host.UI.PromptForChoice($title, $message, $options, 0)
            
            if ($choice -eq 0) {
                Write-Verbose "Creating directory: $Path"
                New-Item -Path $Path -ItemType Directory -Force | Out-Null
            }
            else {
                throw "Path does not exist and was not created: $Path"
            }
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
                
                # Create step files by default (unless -SkipStepFiles is specified)
                if (-not $SkipStepFiles) {
                    # Ensure Steps directory exists
                    if (-not (Test-Path $stepsDir)) {
                        Write-Verbose "Creating Steps directory: $stepsDir"
                        New-Item -Path $stepsDir -ItemType Directory -Force | Out-Null
                    }
                    
                    Write-Verbose "Creating step files..."
                    foreach ($stepName in $StepNames) {
                        if ($PSCmdlet.ShouldProcess("Step-$stepName.ps1", "Create step script")) {
                            try {
                                New-StepperStep -Name $stepName -Path $stepsDir -Force:$Force | Out-Null
                                Write-Host "  Created step: Step-$stepName.ps1" -ForegroundColor Gray
                            }
                            catch {
                                Write-Warning "Failed to create step file for '$stepName': $_"
                            }
                        }
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
