$product = Get-Product "Watcher"
$Name = $product.Name 
$Vendor = $product.Vendor

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Vendor$($emptyString.PadLeft(20-$Vendor.Length," "))","PENDING$($emptyString.PadLeft(27," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message.Split(":")[0],$message.Split(":")[1] -ForegroundColor Gray,DarkGray

Copy-File $PSScriptRoot\templates\definitions\definitions-product-$($product.Id.ToLower())-template.ps1 -Quiet

foreach ($node in (Get-PlatformTopology gallery.nodes -Online -Keys)) {
    New-Log -Name "Watcher" -ComputerName $node | Out-Null
}

$GalleryCimSession = New-CimSession -ComputerName (Get-PlatformTopology gallery.nodes -Online -Keys)

Unregister-CimInstanceEvent -Class Win32_Process -Event __InstanceCreationEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
Unregister-CimInstanceEvent -Class Win32_Process -Event __InstanceDeletionEvent -Name AlteryxServerHost -CimSession $GalleryCimSession

.{ 
    Register-CimInstanceEvent -Class Win32_Process -Event __InstanceCreationEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
    Register-CimInstanceEvent -Class Win32_Process -Event __InstanceDeletionEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
} | Out-Null

.{
    Show-CimInstanceEvent -Class Win32_Process -Event __InstanceCreationEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
    Show-CimInstanceEvent -Class Win32_Process -Event __InstanceDeletionEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
} | 
    Select-Object PSComputerName, FileName, 
        @{"Label"="Name";"Expression"={$_.Name ? $_.Name : $_.Consumer.Name}} | 
    Select-Object @{"Label"="Class";"Expression"={$($_.Name -split "__")[0]}}, 
        @{"Label"="Instance";"Expression"={ $($_.Name -split "__")[1] }}, 
        @{"Label"="Event";"Expression"={ $($_.Name -split "__")[2] }}, 
        @{"Label"="Type";"Expression"={ $($_.Name -split "__")[3] }}, 
        PSComputerName, 
        @{"Label"="LogFile";"Expression"={ $_.FileName }} | 
    Sort-Object -Property Class, Instance, Event, Type, PSComputerName | 
    Format-Table
        
Remove-CimSession $GalleryCimSession

$message = "$($emptyString.PadLeft(8,"`b")) READY$($emptyString.PadLeft(8," "))"
Write-Host+ -NoTrace -NoSeparator -NoTimeStamp $message -ForegroundColor DarkGreen