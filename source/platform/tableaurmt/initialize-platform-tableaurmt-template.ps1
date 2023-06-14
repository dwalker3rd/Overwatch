#region INIT

    Set-CursorInvisible

    Write-Host+
    $message = "<Platform Initialization <.>48> PENDING"
    Write-Host+ -NoTrace -NoNewLine -Parse $message -ForegroundColor DarkBlue,DarkGray,DarkGray

    $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS$($emptyString.PadLeft(8," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen 

    Write-Host+
    Set-CursorVisible

    return

#endregion INIT