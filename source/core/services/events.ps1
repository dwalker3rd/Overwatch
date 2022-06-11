#region SERVICES

function global:Register-CimInstanceEvent {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$true)][string][ValidateSet("Win32_Process","Win32_Service")]$Class,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string][ValidateSet("__InstanceCreationEvent","__InstanceModificationEvent","__InstanceDeletionEvent")]$Event,
        [Parameter(Mandatory=$true)][CimSession[]]$CimSession,
        [Parameter(Mandatory=$false)][string]$LogFilePath  = "$($global:Location.Logs)\$($global:Product.Id).log"
    )

    Write-Debug  "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

    switch ($global:Product.Id) {
        "Watcher" { continue }
        default { throw "Invalid product $($global:Product.Id)" }
    }

    $WQLQuery =  "SELECT * FROM " + $Event + " WITHIN 5 WHERE TargetInstance ISA '" + $Class + "'"
    $WQLQuery += $Name ? " AND TargetInstance.Name like '%" + $Name + "%'" : $null

    $CimSession | ForEach-Object {

        $CimEventFilter = New-CimInstance -CIMSession $_ -ClassName __EventFilter -Namespace "root\Subscription" -Property @{
            Name = $Class + "__" + $Name + $Event + "__Filter"
            EventNameSpace = "root\cimv2"
            QueryLanguage = "WQL"
            Query = $WQLQuery
        }

        $CimLogFileEventConsumer = New-CimInstance -CIMSession $_ -ClassName LogFileEventConsumer -Namespace "root\Subscription" -Property @{
            Name = $Class + "__" + $Name + $Event + "__Consumer"
            Text = "-1,%TIME_CREATED%," + $Class + ",%TargetInstance.Name%," + $Event + ",,,"
            FileName = $LogFilePath
        }

        New-CimInstance -CIMSession $_ -ClassName __FilterToConsumerBinding -Namespace "root\Subscription" -Property @{
            Filter = [Ref] $CimEventFilter
            Consumer = [Ref] $CimLogFileEventConsumer
        }

    }
    
    return

}

function global:Unregister-CimInstanceEvent {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$true)][string][ValidateSet("Win32_Process","Win32_Service")]$Class,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string][ValidateSet("__InstanceCreationEvent","__InstanceModificationEvent","__InstanceDeletionEvent")]$Event,
        [Parameter(Mandatory=$true)][CimSession[]]$CimSession
    )

    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName __EventFilter -Filter "Name = '$($Class)__$($Name)$($Event)__Filter'" | Remove-CimInstance
    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName LogFileEventConsumer -Filter "Name = '$($Class)__$($Name)$($Event)__Consumer'" | Remove-CimInstance
    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName __FilterToConsumerBinding -Filter "__Path like '%$($Class)__$($Name)$($Event)%'" | Remove-CimInstance

    return

}

function global:Show-CimInstanceEvent {

    [CmdletBinding()] 
    param (
        [Parameter(Mandatory=$true)][string][ValidateSet("Win32_Process","Win32_Service")]$Class,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string][ValidateSet("__InstanceCreationEvent","__InstanceModificationEvent","__InstanceDeletionEvent")]$Event,
        [Parameter(Mandatory=$false)][CimSession[]]$CimSession
    )

    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName __EventFilter -Filter "Name = '$($Class)__$($Name)$($Event)__Filter'"
    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName LogFileEventConsumer -Filter "Name = '$($Class)__$($Name)$($Event)__Consumer'"
    Get-CimInstance -CIMSession $CimSession -Namespace "root\Subscription" -ClassName __FilterToConsumerBinding -Filter "__Path like '%$($Class)__$($Name)$($Event)%'" 

    return
}

#endregion SERVICES