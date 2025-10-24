# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Calendar Versioning](https://calver.org/) (YYYY.MM.DD).

## [2025.10.24] - 2025-10-24

### Added

- Initial release of Stepper module
- `Start-Stepper` - Execute step-by-step scripts with automatic state persistence and resume capability
- `Show-StepperStatus` - Display progress tracking and completed steps
- `Get-StepperSteps` - Retrieve step definitions with auto-discovery of JSON configurations
- `Reset-StepperState` - Clear saved state to start fresh
- `New-StepperScript` - Scaffold complete Stepper projects with script, config, and step files
- `New-StepperConfig` - Generate JSON configuration files for step definitions
- `New-StepperStep` - Create individual step script templates
- JSON-based step configuration system with external script files
- Cross-platform state management (Windows, Linux, macOS)
- Automatic state persistence after each step completion
- Data sharing between steps via `AcceptsAllResults` parameter
- Interactive prompts for already-completed steps
- Windows Health Check example demonstrating 4-step workflow
- Test-StepperScript example showcasing scaffolding functionality

### Features

- Cross-platform support with automatic home directory detection
- PowerShell 5.1+ and PowerShell Core compatibility
- PSCustomObject return types for pipeline support
- Error handling and graceful failure recovery
- Auto-resume by default (use `-Fresh` to start over)
- Step enable/disable via JSON configuration
- Professional console output with color-coding and progress indicators
