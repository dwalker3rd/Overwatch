# $global:Product = @{Id = "Monitor"}

if ($(Get-PlatformTask -Id "Monitor")) {
    Unregister-PlatformTask -Id "Monitor" 
}

$subscription = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='eventlog' or @Name='Microsoft-Windows-Eventlog' or @Name='User32'] and (EventID=1074 or EventID=1075 or EventID=6006)]]</Select></Query></QueryList>"        
Register-PlatformTask -Id "Monitor" -execute $pwsh -Argument "$($global:Location.Scripts)\$("Monitor").ps1" -WorkingDirectory $global:Location.Scripts `
    -Once -At $(Get-Date).AddMinutes(5) -RepetitionInterval $(New-TimeSpan -Minutes 5) -RepetitionDuration ([timespan]::MaxValue) `
    -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest `
    -Subscription $subscription

# TESTING
# this duplicates the above subscription, but this approach might be faster and catch more shutdowns
Register-GroupPolicyScript -Path "F:\Overwatch\onshutdown.ps1" -Type "Shutdown" -ComputerName (pt nodes -k)