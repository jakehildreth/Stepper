# ADR 0007: New-StepperScript accepts both -Path and -Name + -Directory parameter sets

**Date:** 2026-05-01
**Status:** Accepted
**Deciders:** Jake Hildreth

---

## Context

`New-StepperScript` needs a way to specify where to write the new script. Two calling styles exist in the wild:

- `New-StepperScript -Path './scripts/Deploy.ps1'` — caller specifies a full path
- `New-StepperScript -Name 'Deploy' -Directory './scripts'` — caller specifies name and location separately; the function constructs the path

Both are idiomatic for PowerShell creation functions. `New-Item` uses `-Path`. `New-ADUser` and similar functions use `-Name` + a location parameter. Some users will have a full path from a variable; others want to type less by specifying just a name.

Supporting only one style forces awkward usage for the other half of callers.

---

## Decision

`New-StepperScript` uses two parameter sets:

- **`ByPath`**: `-Path [string]` (mandatory) — full file path
- **`ByName`**: `-Name [string]` (mandatory) + `-Directory [string]` (optional, defaults to `$PWD`)

Both produce identical output; `ByName` constructs the full path as `Join-Path $Directory "$Name.ps1"`.

A `-Force` switch (common to both sets) overwrites an existing file without error.

---

## Rationale

- `-Path` is the most flexible and explicit
- `-Name` + `-Directory` is less typing for the common "create in current directory" case
- Two parameter sets with no overlap are clean and tab-complete correctly
- `$PWD` default for `-Directory` matches PowerShell convention (`New-Item` behavior)

---

## Consequences

- Parameter set name `ByPath` uses `-Path [string] Mandatory`
- Parameter set name `ByName` uses `-Name [string] Mandatory` and `-Directory [string]` (default `$PWD`)
- `-Force` and `-Showcase` are common parameters across both sets
- Function errors with `FileAlreadyExists` if target path exists and `-Force` is not specified
- Output is `[System.IO.FileInfo]` in all cases
