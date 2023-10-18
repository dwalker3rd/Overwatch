#region INIT

    Write-Host+
    $message = "Platform Initialization"
    $leader = Format-Leader -Length 46 -Adjust $message.Length
    Write-Host+ -NoTrace -NoNewline $message,$leader -ForegroundColor DarkBlue,DarkGray

    try {

        Get-PlatformInfo
     
        if ((Get-PlatformTask -Id SSOMonitor).Status -ne "Running") {
            $result = Start-PlatformTask -Id SSOMonitor
            $result | Out-Null
        }

    }
    catch {
        Write-Host+ -NoTrace -NoTimestamp "FAIL" -ForegroundColor DarkRed 
        Write-Log -Action "Initialize" -Target "Platform" -Status "Fail" -EntryType "Error"
        # throw "[$([datetime]::Now)] Initialize platform ... FAIL"
        return
    }

    Write-Host+ -NoTrace -NoTimestamp "SUCCESS" -ForegroundColor DarkGreen 
    Write-Host+
    
    return

#endregion INIT