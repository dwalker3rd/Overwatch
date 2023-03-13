function global:Get-Files {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$Path = $($(Get-Location).Path),
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Recurse,
        [Parameter(Mandatory=$false)][string]$View
    )

    $params = @{}
    if ($Filter) {$params += @{Filter = $Filter}}
    if ($Recurse) {$params += @{Recurse = $true}}

    $files = @()
    foreach ($node in $ComputerName) {
        $_fileObject = ([FileObject]::new($Path, $node, $params))
        foreach ($_fileInfo in $_fileObject.FileInfo) {
            if ($_fileObject.IsDirectory($_fileInfo)) {
                $files += [DirectoryObject]::new($_fileInfo.FullName)
            }
            else {
                $files += [FileObject]::new($_fileInfo.FullName)
            }
        }
    } 

    return $files #| Select-Object -Property $($View ? $FileObjectView.$($View) : $FileObjectView.Default)

}

function global:Remove-Files {

    [CmdletBinding(
        SupportsShouldProcess
    )]
    Param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$Path = $($(Get-Location).Path),
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Filter,
        [Parameter(Mandatory=$false)][int]$Keep=0,
        [switch]$Days,
        [switch]$Hours,
        [switch]$Recurse,
        [switch]$Force
    )

    # if $Keep -eq 0, then mode is delete
    # if $Keep -gt 0, then mode is purge, retain $Keep number of the most recent files
    # if $Keep -gt 0 -and $Days.IsPresent, then retain $Keep days of the most recent files
    
    $getParams = @{}
    if (![string]::IsNullOrEmpty($ComputerName)) {$getParams += @{ComputerName = $ComputerName}}
    if (![string]::IsNullOrEmpty($Filter)) {$getParams += @{Filter = $Filter}}

    $removeParams = @{}
    if ($Force) {$removeParams += @{Force = $Force}}
    if ($Recurse) {$removeParams += @{Recurse = $Recurse}}   

    $files = Get-Files -Path $Path @getParams

    foreach ($_directoryInfo in $files.DirectoryInfo) {

        if ($Keep -eq 0) {
            # mode is delete
        }
        else {
            # mode is purge
            if ($Days) {
                # retain $Keep days of the most recent directories
                $_directoryInfo = $_directoryInfo | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-$Keep)}
            }
            elseif ($Hours) {
                # retain $Keep days of the most recent directories
                $_directoryInfo = $_directoryInfo | Where-Object {$_.LastWriteTime -lt (Get-Date).AddHours(-$Keep)}
            }
            else {
                # retain $Keep number of the most recent directories
                $_directoryInfo = $_directoryInfo | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip $Keep
            }
        }
        
        if ($_directoryInfo) {
            Write-Host+ -IfVerbose -NoTrace -NoTimestamp "Deleted $($_directoryInfo.FullName)" -ForegroundColor Red
            if($PSCmdlet.ShouldProcess($_directoryInfo.FullName)) {
                Remove-Item $_directoryInfo.FullName -Recurse -Force
            }
        }
    }
    
    foreach ($_fileInfo in $files.FileInfo) {

        if ($Keep -eq 0) {
            # mode is delete
        }
        else {
            # mode is purge
            if ($Days) {
                # retain $Keep days of the most recent files
                $_fileInfo = $_fileInfo | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-$Keep)}
            }
            elseif ($Hours) {
                # retain $Keep days of the most recent files
                $_fileInfo = $_fileInfo | Where-Object {$_.LastWriteTime -lt (Get-Date).AddHours(-$Keep)}
            }
            else {
                # retain $Keep number of the most recent files
                $_fileInfo = $_fileInfo | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip $Keep
            }
        }
        
        if ($_fileInfo) {
            Write-Host+ -IfVerbose -NoTrace -NoTimestamp "Deleted $($_fileInfo.FullName)" -ForegroundColor Red
            if($PSCmdlet.ShouldProcess($_fileInfo.FullName)) {
                Remove-Item $_fileInfo.FullName @removeParams
            }
        }
    }

    return
}

function global:Copy-Files {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName,
        [switch]$Overwrite,
        [switch]$Quiet,
        [switch]$Recurse
    )

    if (!$ComputerName -and $ExcludeComputerName) {
        throw "`$ExcludeComputerName cannot be used when `$ComputerName is null."
    }
    if ($ComputerName -and $ComputerName.Count -eq 1 -and $ComputerName -eq $env:COMPUTERNAME -and $ExcludeComputerName) {
        throw "`$ExcludeComputerName cannot be used when `$ComputerName only contains `$env:COMPUTERNAME."
    }
    if (!$ComputerName -and $Path -eq $Destination) {
        throw "`$Path and `$Destination cannot point to the same location when `$ComputerName is null."
    }

    if ($Path -eq $Destination) { $Destination = $null }

    if ($ComputerName -and $ComputerName.Count -eq 1 -and [string]::IsNullOrEmpty($ExcludeComputerName)) {
        $ExcludeComputerName = $env:COMPUTERNAME
    }

    foreach ($node in $ComputerName) {

        if ($ExcludeComputerName -notcontains $node.ToUpper()) {

            # $files = Get-ChildItem $Path -Recurse:$Recurse.IsPresent
            $files = Get-Files $Path -Recurse:$Recurse.IsPresent

            foreach ($file in $files) {

                if ($file.GetType().Name -eq "DirectoryObject") {
                    $directory = [DirectoryObject]::new($file.Path,$node)
                    if (!$directory.Exists) {
                        $directory.DirectoryInfo.Create()
                    }
                }
                else {
                    $destinationFile = [FileObject]::new(([string]::IsNullOrEmpty($Destination) ? $file.Path : $Destination), $node)
                    Copy-Item -Path $file.Path -Destination $destinationFile.Path -Force:$Overwrite.IsPresent
                    Write-Host+ -NoTrace -NoSeparator -Iff (!$Quiet) "Copy-Item -Path ",$file.Path," -Destination ", $destinationFile.Path -ForegroundColor DarkGray,Gray,DarkGray,Gray
                }
                
            }

        }
    }

}


function global:Edit-Files {

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,Position=0)][string]$Path,
    [Parameter(Mandatory=$true,Position=1)][string]$Find,
    [Parameter(Mandatory=$true,Position=2)][string]$Replace,
    [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME
)

if (Select-String -Path $Path -Pattern $Find) {
    Select-String -Path $Path -Pattern $Find
    (Get-Content -Path $Path) -replace $Find,$Replace | Set-Content -Path $Path
}

return 

}