if ($(Get-PlatformTask -Id "DiskCheck")) {
    Unregister-PlatformTask -Id "DiskCheck"
}