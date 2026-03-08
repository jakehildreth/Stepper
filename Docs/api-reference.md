# API Reference

## `New-Step`

Executes a step in a resumable script. Tracks state by `filepath:lineNumber`.

```powershell
New-Step [-Name] <string> [-ScriptBlock] <scriptblock>
New-Step [-ScriptBlock] <scriptblock>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `Name` | `string` | No | Display name shown in prompts and verbose output |
| `ScriptBlock` | `scriptblock` | Yes | The code to execute |

Must be called from a saved `.ps1` file. Does not work from the console or an unsaved editor buffer.

## `Stop-Stepper`

Removes the state file. Call at the end of every Stepper-enabled script.

```powershell
Stop-Stepper
```

Automatically locates the calling script's state file via the call stack.

## Error Handling

- If a step throws, Stepper propagates a terminating error with step context (identifier, name, number). State is **not** saved for the failed step — on resume, that step re-executes.
- `[CmdletBinding()]` in the calling script is required for error propagation to work correctly.
- All file I/O errors are surfaced as typed `ErrorRecord` objects, not raw exceptions.
