$ProgressPreference='SilentlyContinue'
try{[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12}catch{}
try{[System.Net.WebRequest]::DefaultWebProxy.Credentials=[System.Net.CredentialCache]::DefaultNetworkCredentials}catch{}
$pmLocal="$env:LOCALAPPDATA\PackageManagement"
$pmProg="$env:ProgramFiles\PackageManagement"
$pmData="$env:ProgramData\PackageManagement"
$paths=@($pmLocal,$pmProg,$pmData)
$paths|ForEach-Object{Remove-Item -Recurse -Force $_ -ErrorAction SilentlyContinue}
$cuMods=Join-Path $HOME "Documents\PowerShell\Modules"
New-Item $cuMods -ItemType Directory -Force|Out-Null
$ps7PM="C:\Program Files\PowerShell\7\Modules\PackageManagement\PackageManagement.psd1"
Remove-Module PackageManagement -ErrorAction SilentlyContinue
if(Test-Path $ps7PM){Import-Module $ps7PM -Force}else{Import-Module PackageManagement -Force -ErrorAction SilentlyContinue}
$nugetProviderLoaded=$false
try{
  Import-PackageProvider -Name NuGet -Force -ErrorAction Stop|Out-Null
  $nugetProviderLoaded=$true
}catch{}
if(-not $nugetProviderLoaded){
  $bootstrapSource="https://onegetcdn.azureedge.net/providers/"
  try{
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap -Source $bootstrapSource -ErrorAction Stop|Out-Null
    Import-PackageProvider -Name NuGet -Force|Out-Null
    $nugetProviderLoaded=$true
  }catch{}
}
if(-not $nugetProviderLoaded){
  $ver='2.8.5.208'
  $blob="https://onegetcdn.azureedge.net/providers/Microsoft.PackageManagement.NuGetProvider-$ver.dll"
  $tmp=Join-Path $env:TEMP "Microsoft.PackageManagement.NuGetProvider-$ver.dll"
  try{Invoke-WebRequest $blob -OutFile $tmp -ErrorAction Stop}catch{}
  $bases=@(
    "$env:ProgramFiles\PackageManagement\ProviderAssemblies",
    "$env:LOCALAPPDATA\PackageManagement\ProviderAssemblies",
    "$env:ProgramFiles\PackageManagement\PackageProviders",
    "$env:LOCALAPPDATA\PackageManagement\PackageProviders"
  )
  foreach($b in $bases){
    $t=Join-Path $b "NuGet\$ver"
    New-Item $t -ItemType Directory -Force|Out-Null
    Copy-Item $tmp (Join-Path $t "Microsoft.PackageManagement.NuGetProvider-$ver.dll") -Force -ErrorAction SilentlyContinue
    Copy-Item $tmp (Join-Path $t "Microsoft.PackageManagement.NuGetProvider.dll") -Force -ErrorAction SilentlyContinue
  }
  Remove-Module PackageManagement -ErrorAction SilentlyContinue
  if(Test-Path $ps7PM){Import-Module $ps7PM -Force}else{Import-Module PackageManagement -Force -ErrorAction SilentlyContinue}
  try{
    Import-PackageProvider -Name NuGet -RequiredVersion $ver -Force -ErrorAction Stop|Out-Null
    $nugetProviderLoaded=$true
  }catch{
    try{
      Import-PackageProvider -Name NuGet -Force -ErrorAction Stop|Out-Null
      $nugetProviderLoaded=$true
    }catch{}
  }
}
$havePSGallery=$false
try{
  Import-Module PowerShellGet -Force -ErrorAction Stop|Out-Null
  $havePSGallery=$true
}catch{}
if(-not $havePSGallery){
  $nugetExe=Join-Path $env:TEMP "nuget.exe"
  if(-not (Test-Path $nugetExe)){
    try{Invoke-WebRequest "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetExe -ErrorAction Stop}catch{}
  }
  $dst=Join-Path $env:TEMP "psfix"
  New-Item $dst -ItemType Directory -Force|Out-Null
  try{& $nugetExe install PackageManagement -Source "https://www.powershellgallery.com/api/v2" -OutputDirectory $dst -ExcludeVersion|Out-Null}catch{}
  try{& $nugetExe install PowerShellGet      -Source "https://www.powershellgallery.com/api/v2" -OutputDirectory $dst -ExcludeVersion|Out-Null}catch{}
  $pmSrc=Join-Path $dst "PackageManagement\*"
  $psgSrc=Join-Path $dst "PowerShellGet\*"
  New-Item (Join-Path $cuMods "PackageManagement") -ItemType Directory -Force|Out-Null
  New-Item (Join-Path $cuMods "PowerShellGet") -ItemType Directory -Force|Out-Null
  Copy-Item -Recurse -Force $pmSrc (Join-Path $cuMods "PackageManagement")
  Copy-Item -Recurse -Force $psgSrc (Join-Path $cuMods "PowerShellGet")
  Remove-Module PackageManagement -ErrorAction SilentlyContinue
  if(Test-Path $ps7PM){Import-Module $ps7PM -Force}else{Import-Module PackageManagement -Force -ErrorAction SilentlyContinue}
  Import-Module PowerShellGet -Force -ErrorAction SilentlyContinue
  $havePSGallery=$true
}
try{
  Register-PSRepository -Default -ErrorAction SilentlyContinue
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
}catch{}
$nugetSource='https://api.nuget.org/v3/index.json'
try{
  $src=Get-PackageSource -ErrorAction SilentlyContinue|Where-Object{$_.Name -ieq 'NuGet'}
  if($null -eq $src){
    Register-PackageSource -Name NuGet -Location $nugetSource -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue
  }else{
    Set-PackageSource -Name $src.Name -Location $nugetSource -Trusted -ErrorAction SilentlyContinue
  }
}catch{
  try{
    Unregister-PackageSource -Name NuGet -ErrorAction SilentlyContinue
    Register-PackageSource -Name NuGet -Location $nugetSource -ProviderName NuGet -Trusted -ErrorAction SilentlyContinue
  }catch{}
}
try{Import-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue|Out-Null}catch{}
Write-Host "`n=== Providers ==="
Get-PackageProvider | Select-Object Name,Version,ProviderPath | Format-Table -AutoSize
Write-Host "`n=== Repositories ==="
Get-PSRepository | Select-Object Name,SourceLocation,InstallationPolicy | Format-Table -AutoSize
Write-Host "`n=== Package Sources ==="
Get-PackageSource | Select-Object Name,Location,ProviderName,Trusted | Format-Table -AutoSize
