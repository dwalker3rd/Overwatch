# $global:Product = @{Id = "Watcher"}
# . $PSScriptRoot\definitions.ps1

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