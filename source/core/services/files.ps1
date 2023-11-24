function global:Get-Files {

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false,Position=0)][string[]]$Path = $($(Get-Location).Path),
        [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Recurse,
        [Parameter(Mandatory=$false)][string]$View,
        [Parameter(Mandatory=$false)][int]$Depth,
        [Parameter(Mandatory=$false)][string]$Include,
        [Parameter(Mandatory=$false)][string]$Exclude
    )

    $params = @{}
    if ($Filter) {$params += @{Filter = $Filter}}
    if ($Include) {$params += @{Include = $Include}}
    if ($Exclude) {$params += @{Exclude = $Exclude}}
    if ($Recurse) {
        $params += @{ Recurse = $true }
        if ($null -ne $Depth) { $params += @{ Depth = $Depth } }
    }

    $files = @()
    foreach ($node in $ComputerName) {
        $_fileObject = ([FileObject]::new($Path, $node, $params))
        if ($_fileObject.IsDirectory() -and $params.Count -eq 0) {
            $files += [DirectoryObject]::new($Path, $node)
        }
        else {
            foreach ($_fileInfo in $_fileObject.FileInfo) {
                if ($_fileObject.IsDirectory($_fileInfo)) {
                    $files += [DirectoryObject]::new($_fileInfo.FullName)
                }
                else {
                    $files += [FileObject]::new($_fileInfo.FullName)
                }
            }
        }
    } 

    return $files

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
        [switch]$Force,
        [Parameter(Mandatory=$false)][int]$Depth,
        [Parameter(Mandatory=$false)][string]$Include,
        [Parameter(Mandatory=$false)][string]$Exclude
    )

    # if $Keep -eq 0, then mode is delete
    # if $Keep -gt 0, then mode is purge, retain $Keep number of the most recent files
    # if $Keep -gt 0 -and $Days.IsPresent, then retain $Keep days of the most recent files
    
    $getParams = @{}

    if (![string]::IsNullOrEmpty($ComputerName)) {$getParams += @{ComputerName = $ComputerName}}
    if (![string]::IsNullOrEmpty($Filter)) {$getParams += @{Filter = $Filter}}
    if ($Include) {$params += @{Include = $Include}}
    if ($Exclude) {$params += @{Exclude = $Exclude}}
    if ($Recurse) {
        $params += @{ Recurse = $true }
        if ($null -ne $Depth) { $params += @{ Depth = $Depth } }
    }

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
        [Parameter(Mandatory=$false,Position=1)][string]$Destination = $Path,
        [Parameter(Mandatory=$false)][string[]]$ComputerName,
        [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName,
        [Parameter(Mandatory=$false)][string]$Filter,
        [switch]$Overwrite,
        [switch]$Quiet,
        [switch]$Recurse,
        [Parameter(Mandatory=$false)][int]$Depth,
        [Parameter(Mandatory=$false)][string]$Include,
        [Parameter(Mandatory=$false)][string]$Exclude
    )

    #region VALIDATION

        $regexResult = [regex]::Matches($Destination, $global:RegexPattern.Windows.Unc)
        if (![string]::IsNullOrEmpty($regexResult[0].Groups['computername'].Value)) {
            $ComputerName = $ComputerName | Sort-Object -Unique
        }
        $Destination = $regexResult[0].Groups['path'].Value -replace "\$",":"

        if (!$ComputerName -and $ExcludeComputerName) {
            throw "`$ExcludeComputerName cannot be used when `$ComputerName is null"
        }
        if ($ComputerName -and $ComputerName.Count -eq 1 -and $ComputerName -eq $env:COMPUTERNAME -and $ExcludeComputerName) {
            return
        }
        if (!$ComputerName -and $Path -eq $Destination) {
            throw "`$Path and `$Destination cannot point to the same location when `$ComputerName is null"
        }
        if ($ExcludeComputerName -notcontains $env:COMPUTERNAME -and $ComputerName -contains $env:COMPUTERNAME) {
            $ExcludeComputerName = $env:COMPUTERNAME
            # $ComputerName.Remove($env:COMPUTERNAME)
        }
        if ($Path -eq $Destination) {
            $Destination = $null
        }
        if ($ComputerName -and $ComputerName.Count -eq 1 -and [string]::IsNullOrEmpty($ExcludeComputerName)) {
            $ExcludeComputerName = $env:COMPUTERNAME
        }
        if (!$ComputerName -and !$ExcludeComputerName) {
            $ComputerName = $env:COMPUTERNAME
        }


    #endregion VALIDATION

    $params = @{}
    if ($Filter) {$params += @{Filter = $Filter}}
    if ($Include) {$params += @{Include = $Include}}
    if ($Exclude) {$params += @{Exclude = $Exclude}}
    if ($Recurse) {
        $params += @{ Recurse = $true }
        if ($null -ne $Depth) { $params += @{ Depth = $Depth } }
    }

    # $pathAsFileObject = [FileObject]::new($Path)
    # $sourceDirectory = $pathAsFileObject.IsDirectory() ? $pathAsFileObject : [DirectoryObject]::new($pathAsFileObject.Directory.FullName)
    $sourcefiles = Get-Files $Path @params
    $copyDirectoryandContents = $sourcefiles.count -eq 1 -and $sourcefiles[0].IsDirectory()

    foreach ($node in $ComputerName) {

        if ($ExcludeComputerName -notcontains $node.ToUpper()) {
            
            if ($copyDirectoryandContents) {
                Copy-Item -Path $Path -Destination $Destination -Recurse -Force:$Overwrite.IsPresent
                Write-Host+ -NoTrace -NoSeparator -Iff (!$Quiet) "Copy-Item -Path ", $Path, " -Destination ", $Destination -ForegroundColor DarkGray,Gray,DarkGray,Gray
            }
            else {
                foreach ($sourcefile in $sourcefiles) {

                    # possible states
                    # $Destination is null or empty
                    # $Destination is computername ($Destination modified in validation section above)
                    # $Destination is computername[/share/[directory/[filename]]] ($Destination split in validation section above)
                    # $Destination is share/directory path (no filename) and matches $sourceDirectory
                    # $Destination is share/directory path (no filename) and does NOT match $sourceDirectory
                    # $Destination is share/directory/filename and matches $sourceFile.FullName ($Destination made $null in validation section above)
                    # $Destination is share/directory/filename and does NOT match $sourceFile.FullName

                    if ([string]::IsNullOrEmpty($Destination)) {
                        $destinationFile = [FileObject]::new($sourceFile.Path, $node)
                    }
                    else {
                        $destinationFile = [FileObject]::new($Destination, $node)
                    }
                    $destinationDirectory = $destinationFile.Directory
                    if (!$destinationDirectory.Exists) {
                        New-Item -ItemType Directory -Path $destinationDirectory.FullName -Force | Out-Null
                    }
                    Copy-Item -Path $sourcefile.Path -Destination $destinationFile.Path -Force:$Overwrite.IsPresent
                    Write-Host+ -NoTrace -NoSeparator -Iff (!$Quiet) "Copy-Item -Path ",$sourcefile.Path," -Destination ", $destinationFile.Path -ForegroundColor DarkGray,Gray,DarkGray,Gray
                    
                }
            }

        }

    }

}

function global:Move-Files {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false,Position=1)][string]$Destination,
        [Parameter(Mandatory=$false)][string]$ComputerName = $env:COMPUTERNAME,
        [switch]$Overwrite,
        [switch]$Quiet,
        [switch]$Recurse,
        [Parameter(Mandatory=$false)][int]$Depth,
        [Parameter(Mandatory=$false)][string]$Include,
        [Parameter(Mandatory=$false)][string]$Exclude
    )

    if ($ComputerName -eq $env:COMPUTERNAME -and $Path -eq $Destination) {
        throw "`$Path and `$Destination cannot point to the same location when `$ComputerName is the local machine"
    }
    if ($Path -eq $Destination) { $Destination = $null }

    $params = @{}
    if ($Filter) {$params += @{Filter = $Filter}}
    if ($Include) {$params += @{Include = $Include}}
    if ($Exclude) {$params += @{Exclude = $Exclude}}
    if ($Recurse) {
        $params += @{ Recurse = $true }
        if ($null -ne $Depth) { $params += @{ Depth = $Depth } }
    }

    $files = Get-Files $Path @params
    $moveDirectoryandContents = $files.count -eq 1 -and $files[0].IsDirectory()

    if ($moveDirectoryandContents) {
        $directory = $files[0]
        $destinationDirectory = [DirectoryObject]::new(([string]::IsNullOrEmpty($Destination) ? $directory.Path : $Destination), $ComputerName)
        if (!$destinationDirectory.Exists) {
            New-Item -ItemType Directory $destinationDirectory.Path -ErrorAction SilentlyContinue
        }
        Move-Item -Path $directory.Path -Destination $destinationDirectory.Path -Force:$Overwrite.IsPresent
        Write-Host+ -NoTrace -NoSeparator -Iff (!$Quiet) "Move-Item -Path ",$directory.Path," -Destination ", $destinationDirectory.Path -ForegroundColor DarkGray,Gray,DarkGray,Gray
    }
    else {
        foreach ($file in $files) {
            if ($file.IsDirectory()) {
                $directory = [DirectoryObject]::new($file.Path,$ComputerName)
                if (!$directory.Exists) {
                    $directory.DirectoryInfo.Create()
                }
            }
            else {
                $destinationFile = [FileObject]::new(([string]::IsNullOrEmpty($Destination) ? $file.Path : $Destination), $ComputerName)
                Move-Item -Path $file.Path -Destination $destinationFile.Path -Force:$Overwrite.IsPresent
                Write-Host+ -NoTrace -NoSeparator -Iff (!$Quiet) "Move-Item -Path ",$file.Path," -Destination ", $destinationFile.Path -ForegroundColor DarkGray,Gray,DarkGray,Gray
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

function global:Test-Path+ {
   
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][string]$Path,
        [Parameter(Mandatory=$false)][string]$ComputerName
    )

    if (![string]::IsNullOrEmpty($ComputerName)) {
        return [FileObject]::new($Path,$ComputerName).Exists ? [FileObject]::new($Path,$ComputerName).Exists : [DirectoryObject]::new($Path,$ComputerName).Exists
    }
    else {
        return Test-Path -Path $Path @Args
    }

}