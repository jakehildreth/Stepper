# Troubleshooting

**Stepper says my script has changed**

Script hash mismatch. Choose `[S] Start over` for a clean run, or `[R] Resume (risky)` if you're confident the change doesn't affect completed steps.

**Stepper is prompting about unmanaged code**

Code exists outside `New-Step` blocks. Wrap it in a `New-Step`, mark it with `#region Stepper ignore`, or delete it if it's dead code.

**New-Step doesn't work from the console**

Stepper uses the call stack to find the script file. It must be called from a saved `.ps1` file, not an interactive session.

**The state file is stale / from a previous run I don't want**

Delete the `.stepper` file manually, or select `[S] Start over` at the resume prompt.

**The logo is distracting**

Set `$env:STEPPER_SHOW_LOGO = 'false'` before importing the module.
