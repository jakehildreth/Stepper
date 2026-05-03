# ADR 0012: centralized timestamped backup via New-StepperBackup

**Date:** 2026-05-03
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

Several Stepper functions modify the caller's script on disk:

- `Add-StepperCbh` — injects comment-based help
- `Repair-StepperScript` — adds `[CmdletBinding()]`, install guard
- `Update-ScriptWithUnmanagedActions` — wraps unmanaged code blocks
- `New-Step` — appends `Stop-Stepper`
- `ConvertTo-StepperScript` — rewrites cross-step variable references

Each was independently responsible for producing a backup (or not). `ConvertTo-StepperScript` wrote a flat `<name>.ps1.bak` alongside the source. The other four wrote no backup at all, meaning unrecoverable changes could be made to user scripts silently.

---

## Decision

Introduce `Private/New-StepperBackup.ps1` — a single private function that all script-writing callers invoke immediately before writing. It produces a timestamped backup named:

```
<BaseName>.<yyyy.M.dHHmm>.ps1.bak
```

in the same directory as the source file. The CalVer timestamp matches the project's versioning convention (`yyyy.M.dHHmm`). Existing backups at the same timestamp are silently overwritten (`Copy-Item -Force`), which is safe because the source has not yet been modified at the time of the call.

---

## Rationale

- a single function is easier to test, audit, and change than five scattered patterns
- the CalVer timestamp format is consistent with the project's versioning convention and sorts lexicographically
- placing the backup in the same directory as the source mirrors the `ConvertTo-StepperScript` convention users were already accustomed to
- flat `.bak` suffix with no extension stack (not `.ps1`) was rejected because Windows/macOS file type associations would not be confused by `.ps1.bak`, and keeping `.ps1.bak` makes the backup recognisable as PowerShell source
- backup before every write, even when the change is structural (CBH, guard), is the safe default — users can delete stale backups, but they cannot un-lose overwritten code

---

## Consequences

- `Add-StepperCbh`, `Repair-StepperScript`, `Update-ScriptWithUnmanagedActions`, `New-Step`, and `ConvertTo-StepperScript` each call `New-StepperBackup -Path $ScriptPath | Out-Null` immediately before writing
- `ConvertTo-StepperScript` no longer writes a flat `.ps1.bak`; the timestamped `.ps1.bak` replaces it — existing tests that assert the old flat backup filename are updated accordingly
- repeated runs of a Stepper-enabled script on the same day and hour will overwrite the backup from the same minute (same timestamp); in practice this is fine because the user is running the script interactively and the minute-resolution window is narrow
- the function is `Private` — not exported, not in the manifest's `FunctionsToExport`
