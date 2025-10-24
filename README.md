# Stepper PowerShell Module

A PowerShell module for creating resumable, step-by-step automation scripts with automatic state persistence and cross-platform support.

## Installation

### From PowerShell Gallery (Recommended)
```powershell
Install-Module -Name Stepper -Scope CurrentUser
Import-Module Stepper
```

### From Source
```powershell
git clone https://github.com/jakehildreth/Stepper.git
cd Stepper
Import-Module .\Stepper.psd1 -Force
```

## Quick Start

Create a new Stepper project in seconds:

```powershell
# Create a complete Stepper project
New-StepperScript -Name "My-HealthCheck" -StepNames "CheckDisk", "CheckServices", "GenerateReport"

# Customize the generated step files
code Steps/Step-CheckDisk.ps1
code Steps/Step-CheckServices.ps1
code Steps/Step-GenerateReport.ps1

# Run it!
.\My-HealthCheck.ps1

# If interrupted, just run again - it resumes automatically!
.\My-HealthCheck.ps1
```

## Examples

See the `Examples/` directory for complete working examples:

- **Windows Health Check** - A 4-step system health check demonstrating all module features

```powershell
cd Examples\Windows Health Check
.\Invoke-WindowsHealthCheck.ps1
```

Each example includes detailed documentation and demonstrates best practices for building Steppers.

## Key Functions

- `New-StepperScript` - Create a complete Stepper project
- `New-StepperConfig` - Generate JSON configuration files
- `New-StepperStep` - Create individual step templates
- `Start-Stepper` - Run your Stepper (resumes automatically)
- `Show-StepperStatus` - View current progress
- `Reset-StepperState` - Clear saved state
- `Get-StepperSteps` - List configured steps

Use `Get-Help <function-name> -Full` for detailed documentation on any function.

## License

MIT License - See [LICENSE](LICENSE) for details.

## Version History

See [CHANGELOG.md](CHANGELOG.md) for version history and release notes.
