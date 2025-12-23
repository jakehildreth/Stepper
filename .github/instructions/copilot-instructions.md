### Git Workflow

- Commit messages should be clear and descriptive
- Use conventional commits format: `type(scope): message`
  - Types: feat, fix, docs, style, refactor, test, chore
  - Example: `feat(detection): add ESC13 detection`
  - Example: `refactor(error-handling): use $PSCmdlet.WriteError in Get-AdcsObjects`
  - Example: `fix(validation): add null check for module version in Test-IsLatestVersion`
- **Never use vague messages** like "update XXXXX for internal improvements"
  - ❌ Bad: `refactor: update functions for improvements`
  - ❌ Bad: `chore: update error handling`
  - ✅ Good: `refactor(error-handling): replace Write-Error with $PSCmdlet.WriteError in 8 functions`
  - ✅ Good: `fix(pipeline): add ValueFromPipeline support to Test-IsModuleAvailable`

#### Required Commit Message Detail Level

**All commits must include detailed bullet points** explaining:
1. What files were modified/created
2. What functionality was added/changed
3. What the code detects/does
4. Additional context about the implementation

**Example of required detail level:**
```
feat(detection): add ESC11 detection for CA RPC encryption requirement

- Add ESC11 definition to ESCDefinitions.psd1
- Integrate ESC11 scan into Invoke-Locksmith2.ps1
- Detects CAs with IF_ENFORCEENCRYPTICERTREQUEST flag disabled
- Identifies NTLM relay attack vulnerability
- Provides fix/revert scripts using certutil
```

**Another example:**
```
feat(detection): add ESC6 detection for CA EDITF_ATTRIBUTESUBJECTALTNAME2 flag

- Create Find-VulnerableCA.ps1 for CA-level vulnerability detection
- Add ESC6 definition to ESCDefinitions.psd1
- Integrate ESC6 scan into Invoke-Locksmith2.ps1
- Detects CAs with EDITF_ATTRIBUTESUBJECTALTNAME2 enabled
- Provides fix/revert scripts using certutil
```

- Keep commits atomic and focused
- Update CHANGELOG.MD for user-facing changes
- Be specific about what changed and why

