function global:Initialize-Overwatch {if (Test-Path -Path "$($global:Location.Initialize)\initialize-overwatch.ps1") {. "$($global:Location.Initialize)\initialize-overwatch.ps1"}}
function global:Initialize-OS {if (Test-Path -Path "$($global:Location.Initialize)\initialize-os-$($global:Environ.OS).ps1") {. "$($global:Location.Initialize)\initialize-OS-$($global:Environ.OS).ps1"}}
function global:Initialize-Cloud {if (Test-Path -Path "$($global:Location.Initialize)\initialize-cloud-$($global:Environ.Cloud).ps1") {. "$($global:Location.Initialize)\initialize-cloud-$($global:Environ.Cloud).ps1"}}
function global:Initialize-Platform {if (Test-Path -Path "$($global:Location.Initialize)\initialize-platform-$($global:Environ.Platform).ps1") {. "$($global:Location.Initialize)\initialize-Platform-$($global:Environ.Platform).ps1"}}
function global:Initialize-PlatformInstance {if (Test-Path -Path "$($global:Location.Initialize)\initialize-platformInstance-$($global:Environ.Instance).ps1") {. "$($global:Location.Initialize)\initialize-PlatformInstance-$($global:Environ.Instance).ps1"}}

function global:Initialize-Environment {
    Initialize-Overwatch
    Initialize-OS
    Initialize-Cloud
    Initialize-Platform
    Initialize-PlatformInstance
}
Set-Alias -Name init -Value Initialize-Environment -Scope Global