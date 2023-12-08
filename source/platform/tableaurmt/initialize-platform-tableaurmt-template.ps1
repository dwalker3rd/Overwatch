#region INIT

    Set-CursorInvisible

    Write-Host+
    $message = "<Platform Initialization <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

    Write-Host+ -NoTrace -NoTimeStamp "$($emptyString.PadLeft(8,"`b")) READY  " -ForegroundColor DarkGreen
    Write-Host+

    Write-Host+
    Set-CursorVisible

    return

#endregion INIT