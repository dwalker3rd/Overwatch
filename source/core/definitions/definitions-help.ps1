
if (Test-Path -Path "$($global:Location.Help)/help-OS-$($global:Environ.OS).ps1") {. "$($global:Location.Help)/help-OS-$($global:Environ.OS).ps1"}
if (Test-Path -Path "$($global:Location.Help)/help-Platform-$($global:Environ.Platform).ps1") {. "$($global:Location.Help)/help-Platform-$($global:Environ.Platform).ps1"}
if (Test-Path -Path "$($global:Location.Help)/help-PlatformInstance-$($global:Environ.Instance).ps1") {. "$($global:Location.Help)/help-PlatformInstance-$($global:Environ.Instance).ps1"}
if (Test-Path -Path "$($global:Location.Help)/help-Product-$($global:Environ.Instance).ps1") {. "$($global:Location.Help)/help-Product-$($global:Environ.Instance).ps1"}
if (Test-Path -Path "$($global:Location.Help)/help-Provider-$($global:Environ.Instance).ps1") {. "$($global:Location.Help)/help-Provider-$($global:Environ.Instance).ps1"}