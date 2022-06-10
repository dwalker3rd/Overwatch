$initializePath = $global:Location.Initialize

function global:Initialize-OS {if (Test-Path -Path $initializePath\initialize-OS-$($global:Environ.OS).ps1) {. $initializePath\initialize-OS-$($global:Environ.OS).ps1}}
function global:Initialize-Platform {if (Test-Path -Path $initializePath\initialize-Platform-$($global:Environ.Platform).ps1) {. $initializePath\initialize-Platform-$($global:Environ.Platform).ps1}}
function global:Initialize-PlatformInstance {if (Test-Path -Path $initializePath\initialize-PlatformInstance-$($global:Environ.Instance).ps1) {. $initializePath\initialize-PlatformInstance-$($global:Environ.Instance).ps1}}

function global:Initialize-Environment {
    Initialize-OS
    Initialize-Platform
    Initialize-PlatformInstance
}
Set-Alias -Name init -Value Initialize-Environment -Scope Global
