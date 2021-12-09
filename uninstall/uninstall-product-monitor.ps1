if ($(Get-PlatformTask -Id "Monitor")) {
    Unregister-PlatformTask -Id "Monitor" 
}
