try {
    scoop update --global
}
catch {
    $_progressPreference = $global:ProgressPreference
    $global:ProgressPreference = "SilentlyContinue"
    Invoke-RestMethod get.scoop.sh -outfile "$($global:Location.Temp)\install-scoop.ps1"
    $global:ProgressPreference = $_progressPreference
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    . "$($global:Location.Temp)\install-scoop.ps1" -RunAsAdmin
}
