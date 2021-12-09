if ($(Get-PlatformTask -Id "Cleanup")) {
    Unregister-PlatformTask -Id "Cleanup"
}