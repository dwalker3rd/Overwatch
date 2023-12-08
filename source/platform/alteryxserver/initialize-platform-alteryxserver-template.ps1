#region INIT

    Write-Host+
    $message = "<Platform Initialization <.>48> PENDING"
    Write-Host+ -NoTrace -Parse -NoNewLine $message -ForegroundColor DarkBlue,DarkGray,DarkGray

    try {

        Get-PlatformInfo
     
        if ((Get-PlatformTask -Id SSOMonitor).Status -ne "Running") {
            $result = Start-PlatformTask -Id SSOMonitor
            $result | Out-Null
        }

    }
    catch {
        Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) FAIL" -ForegroundColor DarkYellow
        Write-Host+ -NoTrace -NoSeparator "  $($_.Exception.Message)" -ForegroundColor DarkRed
        Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error"
        # throw "[$([datetime]::Now)] Initialize platform ... FAIL"
        return
    }

    Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) READY  " -ForegroundColor DarkGreen
    Write-Host+
    
    return

#endregion INIT