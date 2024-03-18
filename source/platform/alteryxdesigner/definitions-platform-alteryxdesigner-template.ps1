#region PLATFORM DEFINITIONS

$global:Platform =
[Platform]@{
    Id = "AlteryxDesigner"
    Name = "Alteryx Designer"
    DisplayName = "Alteryx Designer"
    Image = "$($global:Location.Images)/alteryx_a_logo.png"
    Description = ""
}

$global:PlatformDictionary = @{
AlteryxEngine = "AlteryxEngine"
AlteryxEngineCmd = "AlteryxEngineCmd"
AlteryxService = "AlteryxService"
AlteryxServiceProcess = "AlteryxServiceProcess"       
AlteryxGui = "AlteryxGui"
LastRunTime = "Last Run Time"
NextRunTime = "Next Run Time"
Start = "Running"
Stop = "Stopped"
}     

$global:PlatformServiceConfig = @(
[PlatformCim]@{
    Name = "AlteryxService"
    DisplayName = $PlatformDictionary.AlteryxService
    StatusOK = $global:ServiceAnyState
    Required = $true
    Class = "Service"
}
)

$global:PlatformProcessConfig = @(
[PlatformCim]@{
    Name = "AlteryxService"
    DisplayName = $PlatformDictionary.AlteryxServiceProcess
    StatusOK = "Responding"
    Required = $false
    Class = "Process"
},
[PlatformCim]@{
    Name = "AlteryxGui"
    DisplayName = $PlatformDictionary.AlteryxGui
    StatusOK = "Responding"
    Required = $false
    Transient = $true
    Class = "Process"
    Component = "Designer"
},
[PlatformCim]@{
    Name = "AlteryxEngineCmd"
    DisplayName = $PlatformDictionary.AlteryxEngineCmd
    StatusOK = "Responding"
    Required = $false
    Transient = $true
    Class = "Process"
    Component = "Designer"
}
)

# $global:PlatformStatusColor += @{}     

$global:Location += @{
RuntimeSettings = "C:\ProgramData\Alteryx\RuntimeSettings.xml"
}  

#endregion PLATFORM DEFINITIONS