if ($(Get-PlatformTask -Id "AzureADSync")) {
    Unregister-PlatformTask -Id "AzureADSync"
}