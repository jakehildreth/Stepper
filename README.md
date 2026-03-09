![The Stepper logo features the word Stepper in a bold, stylized font with a set of stairs ascending diagonally to the right. The design conveys a sense of progress and upward movement, aligning with the tool's purpose of step-by-step automation. The background is plain, ensuring the logo remains the focal point. Font used: https://www.dafont.com/pix.font?fpp=200](Images/Stepper.png)

# Stepper

A cross-platform PowerShell utility module for creating resumable, step-by-step scripts with automatic state persistence.

![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)
[![PSGallery](https://img.shields.io/powershellgallery/v/Stepper)](https://www.powershellgallery.com/packages/Stepper)
![License](https://img.shields.io/badge/license-MIT%20w%2FCommons%20Clause-green)

---

## Quick Start

```powershell
Install-Module -Name Stepper -Scope CurrentUser -Force
```

Create a `.ps1` script with `New-Step` blocks:

```powershell
#Requires -Modules Stepper   # documents the dependency; Stepper enforces this
[CmdletBinding()]            # required for error propagation and -Verbose support
param()

New-Step 'Download Files' {
    Write-Host "Downloading files..."
    # your code here
}

New-Step 'Process Data' {
    Write-Host "Processing data..."
    # your code here
}

New-Step 'Upload Results' {
    Write-Host "Uploading results..."
    # your code here
}

Stop-Stepper   # removes the state file on successful completion
```

If the script fails inside a `New-Step` block, the next run resumes at the step that failed. All previously completed steps are skipped!

---

## Demo

https://github.com/user-attachments/assets/4717179e-1698-4e19-aac3-e514d04333b8

Created with [VHS](https://github.com/charmbracelet/vhs) by [Charm](https://charm.land).

---

## Learn More

- [How It Works](docs/how-it-works.md) — execution lifecycle, resume logic, verbose output, non-interactive mode
- [Named Steps](docs/named-steps.md) — step names, `$Stepper.StepName`, resume prompt formats
- [Data Persistence](docs/data-persistence.md) — `$Stepper` hashtable, state file schema
- [Unmanaged Code](docs/unmanaged-code.md) — detection, `#region Stepper ignore`, interactive resolution
- [API Reference](docs/api-reference.md) — `New-Step`, `Stop-Stepper`, error handling
- [Examples](docs/examples.md)
- [Troubleshooting](docs/troubleshooting.md)

---

## License

MIT License w/Commons Clause - see [LICENSE](LICENSE) file for details.

---

Made with 💜 by [Jake Hildreth](https://jakehildreth.com)
