#region SERVICES

# Order of service definitions is critical!
# Services do not currently specify dependencies

if (Test-Path -Path "$($global:Location.Services)\services-$($global:Overwatch.Name)-loadearly.ps1") {. "$($global:Location.Services)\services-$($global:Overwatch.Name)-loadearly.ps1"}