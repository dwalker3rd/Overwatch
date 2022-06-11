$helpPath = $global:Location.Help
if (Test-Path -Path $helpPath/help-OS-$($global:Environ.OS).ps1) {. $helpPath/help-OS-$($global:Environ.OS).ps1}
if (Test-Path -Path $helpPath/help-Platform-$($global:Environ.Platform).ps1) {. $helpPath/help-Platform-$($global:Environ.Platform).ps1}
if (Test-Path -Path $helpPath/help-PlatformInstance-$($global:Environ.Instance).ps1) {. $helpPath/help-PlatformInstance-$($global:Environ.Instance).ps1}
if (Test-Path -Path $helpPath/help-Product-$($global:Environ.Instance).ps1) {. $helpPath/help-Product-$($global:Environ.Instance).ps1}
if (Test-Path -Path $helpPath/help-Provider-$($global:Environ.Instance).ps1) {. $helpPath/help-Provider-$($global:Environ.Instance).ps1}