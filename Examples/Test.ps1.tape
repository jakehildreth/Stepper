# VHS documentation
#
# Output:
#   Output <path>.gif               Create a GIF output at the given <path>
#   Output <path>.mp4               Create an MP4 output at the given <path>
#   Output <path>.webm              Create a WebM output at the given <path>
#
# Require:
#   Require <string>                Ensure a program is on the $PATH to proceed
#
# Settings:
#   Set FontSize <number>           Set the font size of the terminal
#   Set FontFamily <string>         Set the font family of the terminal
#   Set Height <number>             Set the height of the terminal
#   Set Width <number>              Set the width of the terminal
#   Set LetterSpacing <float>       Set the font letter spacing (tracking)
#   Set LineHeight <float>          Set the font line height
#   Set LoopOffset <float>%         Set the starting frame offset for the GIF loop
#   Set Theme <json|string>         Set the theme of the terminal
#   Set Padding <number>            Set the padding of the terminal
#   Set Framerate <number>          Set the framerate of the recording
#   Set PlaybackSpeed <float>       Set the playback speed of the recording
#   Set MarginFill <file|#000000>   Set the file or color the margin will be filled with.
#   Set Margin <number>             Set the size of the margin. Has no effect if MarginFill isn't set.
#   Set BorderRadius <number>       Set terminal border radius, in pixels.
#   Set WindowBar <string>          Set window bar type. (one of: Rings, RingsRight, Colorful, ColorfulRight)
#   Set WindowBarSize <number>      Set window bar size, in pixels. Default is 40.
#   Set TypingSpeed <time>          Set the typing speed of the terminal. Default is 50ms.
#
# Sleep:
#   Sleep <time>                    Sleep for a set amount of <time> in seconds
#
# Type:
#   Type[@<time>] "<characters>"    Type <characters> into the terminal with a
#                                   <time> delay between each character
#
# Keys:
#   Escape[@<time>] [number]        Press the Escape key
#   Backspace[@<time>] [number]     Press the Backspace key
#   Delete[@<time>] [number]        Press the Delete key
#   Insert[@<time>] [number]        Press the Insert key
#   Down[@<time>] [number]          Press the Down key
#   Enter[@<time>] [number]         Press the Enter key
#   Space[@<time>] [number]         Press the Space key
#   Tab[@<time>] [number]           Press the Tab key
#   Left[@<time>] [number]          Press the Left Arrow key
#   Right[@<time>] [number]         Press the Right Arrow key
#   Up[@<time>] [number]            Press the Up Arrow key
#   Down[@<time>] [number]          Press the Down Arrow key
#   PageUp[@<time>] [number]        Press the Page Up key
#   PageDown[@<time>] [number]      Press the Page Down key
#   Ctrl+<key>                      Press the Control key + <key> (e.g. Ctrl+C)
#
# Display:
#   Hide                            Hide the subsequent commands from the output
#   Show                            Show the subsequent commands in the output

# Output Test.ps1.gif
Output Test.ps1.mp4
# Output Test.ps1.webm
# Output frames/

Set Shell pwsh
Set FontSize 20
Set FontFamily 'JetBrains Mono'
Set WindowBar Colorful
Set Margin 20
Set MarginFill "#FF00FF"
Set BorderRadius 10
Set Width 1240
Set Height 840

Sleep 500ms
Hide
Type "Import-Module ../Stepper.psd1 -Force"
Enter
Type "Clear-Host"
Enter
Show
Type "# Let's play with Stepper!"
Sleep 500ms
Enter 2
Type "# First, let's take a look at some important lines in the Test.ps1 script!"
Sleep 500ms
Enter

Hide
Type "Clear-Host"
Enter
Show
Type "# Code wrapped in New-Step {} is 'resumable'."
Enter
Type "# If Test.ps1 crashes/hangs/dies during this code block, Test.ps1 will resume"
Enter
Type "# here the next time you run it."
Enter
Type "(Get-Content ./Test.ps1)[1..5]"
Sleep 500ms
Enter
Sleep 5s

Hide
Type "Clear-Host"
Enter
Show
Type "# Code that is NOT wrapped in a New-Step block is not resumable and will"
Enter
Type "# execute every time you run the script."
Enter
Type "(Get-Content ./Test.ps1)[5..12]"
Sleep 500ms
Enter
Sleep 5s

Hide
Type "Clear-Host"
Enter
Show
Type "# In this step of the script, we can simulate a crash by exiting before"
Enter
Type "# the code block ends."
Enter
Type "(Get-Content ./Test.ps1)[12..23]"
Sleep 500ms
Enter
Sleep 5s

Hide
Type "Clear-Host"
Enter
Show
Type "# A variable whose name starts with '$Stepper.' will persist between script"
Enter
Type "# runs and is shared between steps."
Enter
Type "(Get-Content ./Test.ps1)[23..26]"
Sleep 500ms
Enter
Sleep 5s

Hide
Type "Clear-Host"
Enter
Show
Type "# When you first start a Stepper script, Stepper will read the script and"
Enter
Type "# identify issues that may prevent the script from operating as expected."
Enter 2
Type "#  - Missing [CmdletBinding()]"
Enter
Type "#      If CmdletBinding is missing, you can't use the Common Parameters."
Enter
Type "#  - Missing #requires -Modules Stepper statement"
Enter
Type "#      If #requires is missing, it's possible to run a Stepper script without"
Enter
Type "#      Stepper being loaded! Eek!"
Enter
Type "#  - Code that isn't wrapped in New-Step {} blocks"
Enter
Type "#      Non-resumable code may be something you want... but maybe not?"
Enter
Type "#  - Missing Stop-Stepper command at the end of the script"
Enter
Type "#      Stop-Stepper cleans up the state file that stores everything about"
Enter
Type "#      the script's execution state alongside the original script."
Enter 2
Type "# If Stepper identifies any of these issues, it will help you resolve them!"
Enter
Sleep 1s
Enter
Type "# Alright, let's run Test.ps1 and see what happens!"
Sleep 1s
Enter

Hide
Type "Clear-Host"
Enter
Show
Type "./Test.ps1"
Sleep 500ms
Enter
Sleep 5s
Type "A"
Sleep 500ms
Enter
Sleep 1s

Hide
Type "Clear-Host"
Enter
Show
Type "./Test.ps1"
Sleep 500ms
Enter
Sleep 5s
Type "D"
Sleep 1s
Enter
Sleep 3s

Type "M"
Sleep 1s
Enter
Sleep 3s

Type "W"
Sleep 1s
Enter
Sleep 3s

Hide
Type "Clear-Host"
Enter
Show
Type "./Test.ps1"
Sleep 500ms
Enter
Sleep 5s
Type "A"
Sleep 500ms
Enter
Sleep 1s

Hide
Type "Clear-Host"
Enter
Show
Type "./Test.ps1"
Sleep 500ms
Enter
Sleep 1s
Type "Jake"
Sleep 1s
Enter
Sleep 1s

Type "Y"
Sleep 1s
Enter
Sleep 1s

Type "./Test.ps1"
Sleep 500ms
Enter
Sleep 5s
Type "M"
Sleep 500ms
Enter
Sleep 5s
Type "R"
Sleep 500ms
Enter
Sleep 1s
Type "n"
Sleep 500ms
Enter
Sleep 5s
Hide
Type "Clear-Host"
Enter
Show
Enter 10
Type "                      Thanks for trying Stepper! <3"
Sleep 10s
