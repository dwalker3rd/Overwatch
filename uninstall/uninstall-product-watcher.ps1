$GalleryCimSession = New-CimSession -ComputerName (Get-PlatformTopology gallery.nodes -Online -Keys)

Unregister-CimInstanceEvent -Class Win32_Process -Event __InstanceCreationEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
Unregister-CimInstanceEvent -Class Win32_Process -Event __InstanceDeletionEvent -Name AlteryxServerHost -CimSession $GalleryCimSession
        
Remove-CimSession $GalleryCimSession