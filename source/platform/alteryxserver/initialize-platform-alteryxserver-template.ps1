#region INIT

    Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    Write-Host+
    $message = "Platform Initialization"
    $leader = Format-Leader -Length 47 -Adjust $message.Length
    Write-Host+ -NoNewline $message,$leader -ForegroundColor DarkBlue,DarkGray

    try {

        Get-PlatformInfo

    }
    catch {
        Write-Host+ -NoTimestamp -NoTrace "FAIL" -ForegroundColor DarkRed 
        Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error"
        # throw "[$([datetime]::Now)] Initialize platform ... FAIL"
        return
    }

    Write-Host+ -NoTimestamp -NoTrace "SUCCESS" -ForegroundColor DarkGreen 
    Write-Log -Action "Initialize" -Target "Platform" -Status "Success"
    return

#endregion INIT