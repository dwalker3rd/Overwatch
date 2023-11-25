#region PSVERSION

    $PSSupportedVersion = 7
    switch ($PSVersionTable.PSVersion.Major) {
        7 {
            $global:pwsh = "C:\Program Files\PowerShell\$($PSVersionTable.PSVersion.Major)\pwsh.exe"
            $global:PSSessionConfigurationName = "PowerShell.$($PSVersionTable.PSVersion.Major)"
        }
        default {
            throw "Overwatch requires PowerShell $PSSupportedVersion."
        }
    }

#endregion PSVERSION
#region PACKAGE SOURCE

    if (!(Get-PackageSource -ProviderName PowerShellGet)) {
        Register-PackageSource -Name PSGallery -ProviderName PowerShellGet -Trusted -ErrorAction SilentlyContinue | Out-Null
    }
    if (!(Get-PackageSource -ProviderName NuGet -ErrorAction SilentlyContinue)) {
        Register-PackageSource -Name Nuget -Location "https://www.nuget.org/api/v2" -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue | Out-Null
    }

#endregion PACKAGE SOURCE
#region CONSOLE SEQUENCES

    $global:consoleSequence = @{
        Reset = "`e[!p"
        Default = "`e[0m"
        BoldBright = "`e[1m"
        NoBoldBright = "`e[22m"
        Underline = "`e[4m"
        NoUnderline = "`e[24m"
        Negative = "`e[7m"
        Positive = "`e[27m"
        ForegroundBlack = "`e[30m"
        ForegroundRed = "`e[31m"
        ForegroundGreen = "`e[32m"
        ForegroundYellow = "`e[33m"
        ForegroundBlue = "`e[34m"
        ForegroundMagenta = "`e[35m"
        ForegroundCyan = "`e[36m"
        ForegroundWhite = "`e[37m"
        ForegroundExtended = "`e[38m"
        ForegroundDefault = "`e[39m"
        BackgroundBlack = "`e[40m"
        BackgroundRed = "`e[41m"
        BackgroundGreen = "`e[42m"
        BackgroundYellow = "`e[43m"
        BackgroundBlue = "`e[44m"
        BackgroundMagenta = "`e[45m"
        BackgroundCyan = "`e[46m"
        BackgroundWhite = "`e[47m"
        BackgroundExtended = "`e[48m"
        BackgroundDefault = "`e[49m"
        BrightForegroundBlack = "`e[90m"
        BrightForegroundRed = "`e[91m"
        BrightForegroundGreen = "`e[92m"
        BrightForegroundYellow = "`e[93m"
        BrightForegroundBlue = "`e[94m"
        BrightForegroundMagenta = "`e[95m"
        BrightForegroundCyan = "`e[96m"
        BrightForegroundWhite = "`e[97m"
        BrightBackgroundBlack = "`e[100m"
        BrightBackgroundRed = "`e[101m"
        BrightBackgroundGreen = "`e[102m"
        BrightBackgroundYellow = "`e[103m"
        BrightBackgroundBlue = "`e[104m"
        BrightBackgroundMagenta = "`e[105m"
        BrightBackgroundCyan = "`e[106m"
        BrightBackgroundWhite = "`e[107m"

        ForegroundGray = "`e[37m"
        ForegroundDarkGray = "`e[38;2;128;128;128m"
        ForegroundDarkRed = "`e[38;2;139;0;0m"
        BackgroundDarkGray = "`e[48;2;128;128;128m"
        BackgroundDarkRed = "`e[48;2;139;0;0m"
    }
    $global:consoleSequence += @{
        BackgroundForegroundDefault = $global:consoleSequence.BackgroundDefault + $global:consoleSequence.ForegroundDefault
    }

    # set each consoleSequence to an empty string if $global:DisableConsoleSequences is $true
    # this prevents console sequences from being used with incompatible consoles/terminals
    if ($global:DisableConsoleSequences) {
        foreach ($key in @($global:consoleSequence.Keys)) {
            $global:consoleSequence.$key = ""
        }
    }

    #endregion CONSOLE SEQUENCES 
    #region CONSOLE VIRTUAL KEY CODES    

    $global:virtualKeyCode = @{
        CtrlC = 17
    }

#endregion CONSOLE VIRTUAL KEY CODES   
#region CONSOLE METHODS

    function global:Set-CursorVisible { try { [console]::CursorVisible = $true } catch {} }
    function global:Set-CursorInvisible { try { [console]::CursorVisible = $false } catch {} }
    function global:Set-CtrlCAsInput { 
        try { 
            [console]::TreatControlCAsInput = $true
            Clear-ConsoleInputBuffer
        } 
        catch {}
        }
    function global:Set-CtrlCAsInterrupt { try { [console]::TreatControlCAsInput = $false } catch {} }
    function global:Clear-ConsoleInputBuffer { $Host.UI.RawUI.FlushInputBuffer() }
    function global:Read-ConsoleKeyInput { 
        param(
            [Parameter(Mandatory=$false)][string]$ReadKeyOptions
        )
        $key = $null
        if ($Host.UI.RawUI.KeyAvailable) {
            if ($ReadKeyOptions) {
                $key = $Host.UI.RawUI.ReadKey($ReadKeyOptions) 
            }
            elseif ([console]::TreatControlCAsInput) {
                $key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp")
            }
            else {
                key = $Host.UI.RawUI.ReadKey() 
            }
        }
        return $key
    }

#endregion CONSOLE METHODS