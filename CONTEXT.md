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

**Finding**:
A structured result from `Test-StepperScript` that identifies one Error or Warning in a Stepper script, its source location, and its permitted repair type.
_Avoid_: Validation problem, check result, diagnostic item

**Surfaced error**:
A non-terminating error that reached the error stream and console during a step's execution. Counted and reported per step; never fails the step.

**Silenced error**:
A non-terminating error suppressed with `-ErrorAction SilentlyContinue` inside a step; recorded in `$Error` but not displayed. Counted and reported separately from surfaced errors; never fails the step.
