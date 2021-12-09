if ($(Get-PlatformTask -Id "AzureADCache")) {
    Unregister-PlatformTask -Id "AzureADCache"
}