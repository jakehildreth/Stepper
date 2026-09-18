# Stepper

Stepper makes PowerShell scripts resumable by dividing their work into persistent execution steps and coordinating the script lifecycle around those steps.

## Language

**Stepper script**:
A PowerShell script that opts into the Stepper lifecycle by containing `Start-Stepper`/`Initialize-Stepper`, `New-Step`, or `Stop-Stepper`.
_Avoid_: Stepper-managed script, managed script

**Lifecycle command**:
A command that controls a Stepper script's lifecycle rather than performing the script's resumable work: Start, New Step, or Stop.
_Avoid_: Control command, framework command

**Managed code**:
Executable user code contained within a `New-Step` block and therefore governed by Stepper's resume behavior.
_Avoid_: Step code, wrapped code

**Ignored code**:
Executable code deliberately exempted from step management and unmanaged-code review by a paired Stepper-ignore region.
_Avoid_: Excluded code, skipped code

**Unmanaged code**:
Executable user code outside both `New-Step` blocks and Stepper-ignore regions; lifecycle commands themselves are not unmanaged code.
_Avoid_: Loose code, unwrapped code
