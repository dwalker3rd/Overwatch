if ($(Get-PlatformTask -Id "Backup")) {
    Unregister-PlatformTask -Id "Backup"
}