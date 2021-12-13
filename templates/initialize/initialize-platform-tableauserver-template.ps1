#region INIT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
    
    Write-Host+ ""
    $message = "Platform Initialization"
    $dots = Write-Dots -Length 47 -Adjust (-($message.Length))
    Write-Host+ -NoNewline $message,$dots -ForegroundColor DarkBlue,DarkGray

    try {

        # Get-PlatformInfo
        Initialize-TsmApiConfiguration
        Initialize-TSRestApiConfiguration

    }
    catch {
        Write-Host+ -NoTimestamp -NoTrace " FAIL" -ForegroundColor DarkRed 
        Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error" -Message $_.Exception.Message
        # throw "[$([datetime]::Now)] Initialize platform ... FAIL"
        return
    }

    Write-Host+ -NoTimestamp -NoTrace " DONE" -ForegroundColor DarkGreen 
    Write-Log -Action "Initialize" -Target "Platform" -Status "Success"

    return

#endregion INIT