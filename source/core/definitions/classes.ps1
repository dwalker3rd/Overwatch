#region CLASS DEFINITIONS

using namespace System.IO

class CatalogObject {

    [ValidateNotNullOrEmpty()][string]$Type
    [ValidateNotNullOrEmpty()][string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Publisher
    [string]$Release
    [string]$Suite
    [string]$Image
    [object]$Initialization
    [object]$Installation
    hidden [string]$SortProperty
    [bool]$Installed

    CatalogObject() { $this.Init() }

    [void]Init() {
        $this.Refresh()
    }

    [void]Refresh() {
        $this.Type = $this.GetType().Name
        $this.Installed = $this.IsInstalled()
        $this.SortProperty = $this.GetSortProperty()
    }

    [string]Uid() {
        return "$($this.Type).$($this.Id)"
    }

    [bool]IsInstalled() {
        return $this.Id -in $global:Environ.$($this.Type)
    }

    hidden [string]GetSortProperty() {
        $_typeSortOrder =  @{ CatalogObject = 0; Overwatch = 1; OS = 2; Cloud = 3; Platform = 4; Product = 5; Provider = 6 }
        return "$($_typeSortOrder.($this.Type))$(![string]::IsNullOrEmpty($this.Id) ? ".$($this.Id)" : $null)"
    }

    [string[]]Properties() {

        $_properties = @()

        # get the base class properties
        $_baseObjectProperties = @()
        try { 
            $_baseObjectProperties += ($this.GetType()).BaseType.GetProperties() | 
                Where-Object {$_.CustomAttributes.AttributeType.Name -ne "HiddenAttribute"}
            if ($_baseObjectProperties) { $_properties += $_baseObjectProperties }
        } catch {}

        # get properties in object that aren't in the base class
        $_thisObjectProperties = @()
        $_thisObjectProperties += ($this.GetType()).GetProperties() | 
            Where-Object {$_.CustomAttributes.AttributeType.Name -ne "HiddenAttribute"} |
                Where-Object {$_.Name -notin $_baseObjectProperties.Name}

        $_properties += $_thisObjectProperties

        return $_properties.Name

    }

}

class Overwatch : CatalogObject {}

class OS : CatalogObject {}

class Cloud : CatalogObject {
    [string]$Version
    [string]$Build
    [System.Uri]$Uri
    [string]$Log
}

class Platform : CatalogObject {
    [string]$Instance
    [string]$Version
    [string]$Build
    [System.Uri]$Uri
    [string]$Domain
    [string]$InstallPath
    [string]$Log
}

class PlatformStatus {
    [bool]$IsOK
    [string]$RollupStatus
    [object[]]$Issues
    #region PLATFORM EVENT
        [string]$Event
        [string]$EventReason
        [string]$EventStatus
        [string]$EventStatusTarget
        [string]$EventCreatedBy
        [datetime]$EventCreatedAt
        [datetime]$EventUpdatedAt
        [datetime]$EventCompletedAt
        [bool]$EventHasCompleted
    #endregion PLATFORM EVENT
    [PlatformCim[]]$ByCimInstance
    [object]$StatusObject
    [bool]$IsStopped 
    [bool]$IsStoppedTimeout
    [bool]$Intervention
    [string]$InterventionReason
}

# if the PlatformEvent class is changed, the installer must
# migrate the PlatformEventHistory cache to the new class
class PlatformEvent {
    [string]$Event
    [string]$EventReason
    [string]$EventStatus
    [string]$EventStatusTarget
    [string]$EventCreatedBy
    [datetime]$EventCreatedAt
    [datetime]$EventUpdatedAt
    [datetime]$EventCompletedAt
    [bool]$EventHasCompleted
    [string]$ComputerName
    [datetime]$TimeStamp
}

class PlatformCim {
    [int]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Status
    [string]$Node
    [string[]]$StatusOK 
    [bool]$Required
    [bool]$Transient
    [bool]$IsOK
    [string]$Class
    [object]$Instance
    [string]$Description
    [string[]]$ParentName
    [object]$ParentInstance
    [int]$ParentId
    [string]$ProductID
    [string[]]$Component
}

class Product : CatalogObject {
    [string]$Status
    [bool]$HasTask
    [string]$TaskName
    [string]$Log
    [object]$Config
    [timespan]$ShutdownMax
}

class Provider : CatalogObject {
    [string]$Category
    [string]$SubCategory
    [string]$Log
    [object]$Config
}

class Heartbeat {
    [bool]$IsOK
    [string]$Status
    [bool]$PlatformIsOK
    [string]$PlatformRollupStatus
    [bool]$Alert
    [object[]]$Issues
    [datetime]$TimeStamp
    [bool]$FlapDetectionEnabled
    [timespan]$FlapDetectionPeriod
    [bool]$ReportEnabled 
    [object[]]$ReportSchedule
    [DateTime]$PreviousReport
    [TimeSpan]$SincePreviousReport  
}

# if the HeartbeatHistory class is changed, the installer must
# migrate the HeartbeatHistory cache to the new class
class HeartbeatHistory {
    [bool]$IsOK
    [string]$Status
    [bool]$PlatformIsOK
    [string]$PlatformRollupStatus
    [bool]$Alert
    [object[]]$Issues
    [datetime]$TimeStamp
}
    
class PerformanceMeasurement {
    [string]$Class
    [string]$Instance 
    [string]$Counter
    [string]$Name
    [double[]]$Raw
    [double]$Value
    [datetime[]]$TimeStamp
    [string]$Suffix
    [double]$Factor=1
    [string]$Text
    [bool]$SingleSampleOnly=$false
    [string]$ComputerName
}

class DirectoryObject {

    [ValidateNotNullOrEmpty()]
    [string]$Path

    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$ComputerName

    [string]$OriginalPath
    [string]$FullPath
    [string]$Root
    [string]$Parent

    [DirectoryInfo]$DirectoryInfo

    DirectoryObject() {}
    DirectoryObject([string]$Path) { $this.Init($Path,$env:COMPUTERNAME) }
    DirectoryObject([string]$Path,[string]$ComputerName) { $this.Init($Path,$ComputerName) }
    
    [void]Init(
        [string]$Path,
        [string]$ComputerName
    ) {
        # validate
        $this.Validate($Path, $ComputerName)

        $this.OriginalPath = $Path
        $this.FullPath = [Path]::GetFullPath($Path)
        $this.ComputerName = $ComputerName
        $this.Path = $this.ToUnc($this.FullPath,$ComputerName)

        $this.Parent = $this.GetParent()
        $this.Root = $this.GetDirectoryRoot()

        $this.DirectoryInfo = [DirectoryInfo]::New($this.Path)

    }

    [void]Validate([string]$Path,[string]$ComputerName) {

        if (!(Test-Path -Path $Path -IsValid)) {
            throw "[Test-Path -IsValid] Path '$($Path)' is invalid."
        }
        if ($ComputerName -notmatch '^[a-z0-9-]+$') {
            throw "[Regex] ComputerName '$($ComputerName)' contains invalid characters."
        }

        if (!(Test-WSMan $ComputerName)) {
            throw "[Test-WSMan] Unable to resolve or connect to ComputerName '$($ComputerName)'."
        }

    }

    [void]CreateDirectory() { $this.CreateDirectory($this.Path) }
    [void]CreateDirectory([string]$Path) { if (!$this.Exists($Path)) { $this.DirectoryInfo = [Directory]::CreateDirectory($Path) } }
    [void]Delete() { $this.Delete($this.Path, $false) }
    [bool]Exists() {return $this.Exists($this.Path) }
    [bool]Exists([string]$Path) {return [Directory]::Exists($Path) }
    [datetime]GetCreationTime() { return [Directory]::GetCreationTime($this.Path) }
    [datetime]GetCreationTimeUtc() { return [Directory]::GetCreationTimeUtc($this.Path) }
    [string[]]GetDirectories() {return [Directory]::GetDirectories($this.Path)}
    [string[]]GetDirectories([string]$searchPattern) {return [Directory]::GetDirectories($this.Path,$searchPattern,[SearchOption]::TopDirectoryOnly)}
    [string[]]GetDirectories([SearchOption]$searchOption) {return [Directory]::GetDirectories($this.Path,"*",$searchOption)}
    [string[]]GetDirectories([string]$searchPattern,[SearchOption]$searchOption) {return [Directory]::GetDirectories($this.Path,$searchPattern,$searchOption)}
    [string[]]GetDirectoryRoot() {return [Directory]::GetDirectoryRoot($this.Path)}
    [string[]]GetFiles() {return [Directory]::GetFiles($this.Path)}
    [string[]]GetFiles([string]$searchPattern) {return [Directory]::GetFiles($this.Path,$searchPattern,[SearchOption]::TopDirectoryOnly)}
    [string[]]GetFiles([SearchOption]$searchOption) {return [Directory]::GetFiles($this.Path,"*",$searchOption)}
    [string[]]GetFiles([string]$searchPattern,[SearchOption]$searchOption) {return [Directory]::GetFiles($this.Path,$searchPattern,$searchOption)}
    [datetime]GetLastAccessTime() { return [Directory]::GetLastAccessTime($this.Path) }
    [datetime]GetLastAccessTimeUtc() { return [Directory]::GetLastAccessTimeUtc($this.Path) }
    [datetime]GetLastWriteTime() { return [Directory]::GetLastWriteTime($this.Path) }
    [datetime]GetLastWriteTimeUtc() { return [Directory]::GetLastWriteTimeUtc($this.Path) }
    [object]GetParent() { return [Directory]::GetParent($this.Path) }
    [void]Move([string]$Destination) { [Directory]::Move($this.Path, $Destination) }
    [void]SetCurrentDirectory() { [Directory]::SetCurrentDirectory($this.Path) }
    
    [string]ToUnc() { return $this.ToUnc($this.Path, $this.ComputerName) }
    [string]ToUnc([string]$Path, [string]$ComputerName) { return $Path -replace "^([a-zA-Z])\:","\\$($ComputerName)\`$1`$" }

}

class FileObject {
    [ValidateNotNullOrEmpty()]
    [string]$Path

    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$ComputerName

    [string]$FullPathName
    [string]$PathRoot
    [string]$Directory
    [string]$FileName
    [string]$FileNameWithoutExtension
    [string]$Extension

    [object]$FileInfo

    hidden [string]$ValidFileNameExtension = "\..+$"

    FileObject() {}
    FileObject([string]$Path) { $this.Init($Path,$env:COMPUTERNAME,@{}) }
    FileObject([string]$Path,[string]$ComputerName) { $this.Init($Path,$ComputerName,@{}) }
    FileObject([string]$Path,[string]$ComputerName,[hashtable]$Options) { $this.Init($Path,$ComputerName,$Options) }
    
    [void] Init(
        [string]$Path,
        [string]$ComputerName,
        [hashtable]$Options
    ) {
        # validate
        if (!$this.IsValidPath($Path)) {return}
        if (!$this.IsValidComputer($ComputerName)) {return}

        $this.Path = $this.ToUnc($Path, $ComputerName)
        $this.ComputerName = $ComputerName

        $this.FullPathName = [Path]::GetFullPath($this.Path)
        $this.PathRoot = [Path]::GetPathRoot($this.FullPathName)

        if ($this.IsDirectory()) {
            $this.Directory = $this.FullPathName
            # Write-Warning "Use the DirectoryObject class for directories."
        }
        else {
            $this.Directory = [Path]::GetDirectoryName($this.FullPathName)
            $this.FileName = [Path]::GetFileName($this.FullPathName)
            $this.FileNameWithoutExtension = [Path]::GetFileNameWithoutExtension($this.FullPathName)
            $this.Extension = [Path]::GetExtension($this.FullPathName)
        }

        #actions
        $this.Get($Options)

    }

    [bool]IsValidPath(
        [string]$Path
    ) {
        # path spec
        if (!$(Test-Path $Path -IsValid)) {
            Write-Warning "Invalid path '$($Path)'."
            return $false
        }

        # filename extension
        if (!$this.IsDirectory($Path)) {
            $filenameExtension = [Path]::GetExtension($Path)
            if ($filenameExtension -notmatch $this.ValidFileNameExtension) {
                Write-Warning "Invalid filename extension '$($filenameExtension)' for [$($this.GetType())]."
                return $false
            }
        }

        # otherwise
        return $true
    }

    [bool]IsValidComputer(
        [string]$ComputerName
    ) {
        # valid characters
        if ($ComputerName -notmatch '^[a-z0-9-]+$') {
            Write-Warning "The computer name '$($ComputerName)' contains invalid characters."
            return $false
        }

        # powershell remoting 
        if (!(Test-WSMan $ComputerName)) {
            Write-Warning "[Test-WSMan]: The computer name '$($ComputerName)' cannot be resolved."
            return $false
        }

        # otherwise
        return $true
    }

    [object]New(
    ) {
        if ($this.Exists($this.Path)) {
            Write-Warning "The file '$($this.Path)' already exists."
            return $null}
        if (!$this.Exists($this.Directory)) {
            Write-Warning "Could not find a part of the path '$($this.Path)'"
            return $null
        }

        $this.FileInfo = New-Item -Path $this.Path -ItemType File

        if (!$this.FileInfo) {
            Write-Warning "Unable to create '$($this.Path)'"
            return $null
        }

        return $this.FileInfo
    }

    [object]Get(
    ) {
        return $this.Get(@{})
    }
    [object]Get(
        [hashtable]$Options
    ) {
        $this.FileInfo = Get-ChildItem -Path $this.Path @Options -ErrorAction SilentlyContinue
        return $this.FileInfo
    }

    [void]Remove(
    ) {
        if (!$this.FileInfo) {
            Write-Warning "FileInfo is null."
            return}

        foreach ($file in $this.FileInfo.FullName) {
            if (!$this.Exists($file)) {
                Write-Warning "Could not find a part of the path '$($this.FileInfo.FullName)'"
                return
            }
        }

        $this.FileInfo.Delete()
    }

    [bool]Exists() {return $this.Exists($this.Path) }
    [bool]Exists([string]$Path) {return Test-Path $Path}

    [bool]IsUnc([string]$Path) {return $Path -match "^\\\\[^\.\?].+$"}
    
    [string]ToUnc(
        [string]$Path,
        [string]$ComputerName
    ) {
        if (!$this.IsValidPath($Path)) {return $null}
        if (!$this.IsValidComputer($ComputerName)) {return $null}

        if ($this.IsUnc($Path)) {return $Path}
        return [Path]::GetFullPath($Path) -replace "^([a-zA-Z])\:","\\$($ComputerName)\`$1`$" 
    }
    
    [bool]IsLocal() {return $env:COMPUTERNAME -eq $this.ComputerName}
    [bool]IsRemote() {return !$this.IsLocal() }

    [bool]IsDirectory() {return $this.IsDirectory($this.Path) }
    [bool]IsDirectory([string]$Path) {return Test-Path $Path -PathType Container}

    [bool]IsFile() {return $this.IsFile($this.Path) }
    [bool]IsFile([string]$Path) {return Test-Path $Path -PathType Leaf}

    [int]FileCount() {return $(Resolve-Path $this.Path).Length}
    [bool]IsSingleFile() {return $this.FileCount() -eq 1}
}

class LogObject : FileObject {

    [string]$Name

    hidden [string]$ValidFileNameExtension = "^\.log$"

    LogObject():base() {}
    LogObject([string]$Path) { ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{}); $this.Init() }
    LogObject([string]$Path,[string]$ComputerName) { ([FileObject]$this).Init($Path,$ComputerName,@{}); $this.Init() }  
    LogObject([string]$Path,[string]$ComputerName,[hashtable]$Options) { ([FileObject]$this).Init($Path,$ComputerName,$Options); $this.Init() }  

    [void]Validate() {}

    [void]Init(
    ) {
        # properties
        # $this.Name = (Get-Culture).TextInfo.ToTitleCase($this.FileNameWithoutExtension)
        $this.Name = $this.FileNameWithoutExtension

        # validate
        $this.Validate()
    }

    [object]New(
        [object]$Header
    ) {
        if (([FileObject]$this).New()) {
            Add-Content -Path $this.Path -Value $Header
        }
        return $this.FileInfo
    }

    [int]Count() {return $(Import-Csv -Path $this.Path).Count}

}

class CacheObject : FileObject {
    
    [string]$Name
    [timespan]$MaxAge

    hidden [string]$ValidFileNameExtension = "^\.cache$"

    CacheObject():base() {}
    CacheObject([string]$Path) { ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{});$this.Init([timespan]::MaxValue) }
    CacheObject([string]$Path,[string]$ComputerName) { ([FileObject]$this).Init($Path,$ComputerName,@{});$this.Init([timespan]::MaxValue) }
    CacheObject([string]$Path,[string]$ComputerName,[timespan]$MaxAge) { ([FileObject]$this).Init($Path,$ComputerName,@{});$this.Init($MaxAge) }
    CacheObject([string]$Path,[string]$ComputerName,[hashtable]$Options) { ([FileObject]$this).Init($Path,$ComputerName,$Options);$this.Init([timespan]::MaxValue) }  
    CacheObject([string]$Path,[string]$ComputerName,[timespan]$MaxAge,[hashtable]$Options) { ([FileObject]$this).Init($Path,$ComputerName,$Options);$this.Init($MaxAge) }          

    [void]Validate() {}

    [void]Init(
        [timespan]$MaxAge
    ) {
        # params
        $this.MaxAge = $MaxAge
        
        # properties
        $this.Name = (Get-Culture).TextInfo.ToTitleCase($this.FileNameWithoutExtension)

        # validate
        $this.Validate()
    }

    [timespan]Age() {return $this.FileInfo.LastWriteTime ? [datetime]::Now - $this.FileInfo.LastWriteTime : $null}
    [bool]Expired() {return $this.Age() -gt $this.MaxAge}
    [bool]Expired([timespan]$MaxAge) {return $this.Age() -gt $MaxAge}
}

class VaultObject : FileObject {
    
    [string]$Name

    hidden [string]$ValidFileNameExtension = "^\.vault$"

    VaultObject():base() {}
    VaultObject([string]$Path) { ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{});$this.Init() }
    VaultObject([string]$Path,[hashtable]$Options) { ([FileObject]$this).Init($Path,$env:COMPUTERNAME,$Options);$this.Init() } 
    VaultObject([string]$Path,[string]$ComputerName) { ([FileObject]$this).Init($Path,$ComputerName,@{});$this.Init() }      
    VaultObject([string]$Path,[string]$ComputerName,[hashtable]$Options) { ([FileObject]$this).Init($Path,$ComputerName,$Options);$this.Init() }     

    [void]Validate() {}

    [void]Init(
    ) {
        # params
        
        # properties
        $this.Name = (Get-Culture).TextInfo.ToTitleCase($this.FileNameWithoutExtension)

        # validate
        $this.Validate()
    }
    
}

class LogEntry {
    [int]$Index 
    [datetime]$TimeStamp 
    [string]$EntryType
    [string]$Context
    [string]$Action
    [string]$Status 
    [string]$Target
    [string]$Message
    [string]$Data
    [string]$ComputerName
}

class Contact {
    [string]$Name
    [string]$Email
    [string]$Phone
}

#endregion CLASS DEFINITIONS