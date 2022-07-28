#region CLASS DEFINITIONS

using namespace System.IO

class Overwatch {
    [string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Image
    [string]$Version
    [string]$Log
}

class OS {
    [string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Image
    [string]$Version
    [string]$Log
}

class Platform {
    [string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Image
    [string]$Instance
    [string]$Version
    [string]$Build
    [string]$Log
    [System.Uri]$Uri
    [string]$Domain
    [string]$Publisher
    [string]$InstallPath
    [object]$Api
    [object]$Installation
}

class PlatformStatus {
    [bool]$IsOK
    [string]$RollupStatus

    [string]$Event
    [string]$EventReason
    [string]$EventStatus
    [string]$EventCreatedBy
    [datetime]$EventCreatedAt
    [datetime]$EventUpdatedAt
    [datetime]$EventCompletedAt
    [bool]$EventHasCompleted
    [string]$EventStatusTarget

    [PlatformCim[]]$ByCimInstance
    [object]$StatusObject

    [bool]$IsStopped 
    [bool]$IsStoppedTimeout

    [bool]$Intervention
    [string]$InterventionReason
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
    [string]$ParentName
    [object]$ParentInstance
    [int]$ParentId
    [string]$ProductID
    [string[]]$Component
}

class Product {
    [string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Image
    [string]$Version
    [string]$Log
    [bool]$IsInstalled
    [timespan]$ShutdownMax
    [string]$Status
    [bool]$HasTask
    [string]$TaskName
    [object]$Config
    [string]$Publisher
    [object]$Installation
}

class Provider {
    [string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Image
    [string]$Category
    [string]$SubCategory
    [string]$Version
    [string]$Log
    [object]$Config
    [string]$Publisher
    [object]$Installation
    [bool]$IsInstalled
}

class Heartbeat {
    [DateTime]$Current   
    [DateTime]$Previous
    # [object[]]$ReportSchedule
    # [bool]$ReportEnabled 
    [DateTime]$PreviousReport
    [TimeSpan]$SincePreviousReport    
    [bool]$IsOKCurrent
    [bool]$IsOKPrevious
    [bool]$IsOK
    # [bool]$FlapDetectionEnabled
    # [timespan]$FlapDetectionPeriod
    [string]$RollupStatus
    [string]$RollupStatusPrevious
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

class FileObject {
    [ValidateNotNullOrEmpty()][string]$Path

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

    FileObject(){}
    FileObject([string]$Path) {$this.Init($Path,$env:COMPUTERNAME,@{})}
    FileObject([string]$Path,[string]$ComputerName) {$this.Init($Path,$ComputerName,@{})}
    FileObject([string]$Path,[string]$ComputerName,[hashtable]$Options) {$this.Init($Path,$ComputerName,$Options)}
    
    [void] Init(
        [string]$Path,
        [string]$ComputerName,
        [hashtable]$Options
    ){
        # validate
        if (!$this.IsValidPath($Path)) {return}
        if (!$this.IsValidComputer($ComputerName)) {return}

        $this.Path = $this.ToUnc($Path, $ComputerName)
        $this.ComputerName = $ComputerName

        $this.FullPathName = [Path]::GetFullPath($this.Path)
        $this.PathRoot = [Path]::GetPathRoot($this.FullPathName)

        if ($this.IsDirectory()) {
            $this.Directory = $this.FullPathName
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
    ){
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
    ){
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
    ){
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
    ){
        return $this.Get(@{})
    }
    [object]Get(
        [hashtable]$Options
    ){
        $this.FileInfo = Get-ChildItem -Path $this.Path @Options -ErrorAction SilentlyContinue
        return $this.FileInfo
    }

    [void]Remove(
    ){
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

    [bool]Exists() {return $this.Exists($this.Path)}
    [bool]Exists([string]$Path) {return Test-Path $Path}

    [bool]IsUnc([string]$Path) {return $Path -match "^\\\\[^\.\?].+$"}
    
    [string]ToUnc(
        [string]$Path,
        [string]$ComputerName
    ){
        if (!$this.IsValidPath($Path)) {return $null}
        if (!$this.IsValidComputer($ComputerName)) {return $null}

        if ($this.IsUnc($Path)) {return $Path}
        return [Path]::GetFullPath($Path) -replace "^([a-zA-Z])\:","\\$($ComputerName)\`$1`$" 
    }
    
    [bool]IsLocal() {return $env:COMPUTERNAME -eq $this.ComputerName}
    [bool]IsRemote() {return !$this.IsLocal()}

    [bool]IsDirectory() {return $this.IsDirectory($this.Path)}
    [bool]IsDirectory([string]$Path) {return Test-Path $Path -PathType Container}

    [bool]IsFile() {return $this.IsFile($this.Path)}
    [bool]IsFile([string]$Path) {return Test-Path $Path -PathType Leaf}

    [int]FileCount() {return $(Resolve-Path $this.Path).Length}
    [bool]IsSingleFile() {return $this.FileCount() -eq 1}
}

class LogObject : FileObject {

    [string]$Name

    hidden [string]$ValidFileNameExtension = "^\.log$"

    LogObject():base(){}
    LogObject([string]$Path) {
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{})
        $this.Init()}
    LogObject([string]$Path,[string]$ComputerName) {
        ([FileObject]$this).Init($Path,$ComputerName,@{})
        $this.Init()}  
    LogObject([string]$Path,[string]$ComputerName,[hashtable]$Options) {
        ([FileObject]$this).Init($Path,$ComputerName,$Options)
        $this.Init()}  

    [void]Validate() {}

    [void]Init(
    ){
        # properties
        $this.Name = (Get-Culture).TextInfo.ToTitleCase($this.FileNameWithoutExtension)

        # validate
        $this.Validate()
    }

    [object]New(
        [object]$Header
    ){
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

    CacheObject():base(){}
    CacheObject(
        [string]$Path
    ){
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{})
        $this.Init([timespan]::MaxValue)
    }
    CacheObject(
        [string]$Path,
        [timespan]$MaxAge
    ){
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{})
        $this.Init($MaxAge)}  
    CacheObject(
        [string]$Path,
        [timespan]$MaxAge,
        [hashtable]$Options
    ){
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,$Options)
        $this.Init($MaxAge)}          

    [void]Validate(){}

    [void]Init(
        [timespan]$MaxAge
    ){
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

    VaultObject():base(){}
    VaultObject(
        [string]$Path
    ){
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,@{})
        $this.Init()
    }
    VaultObject(
        [string]$Path,
        [hashtable]$Options
    ){
        ([FileObject]$this).Init($Path,$env:COMPUTERNAME,$Options)
        $this.Init()
    }          

    [void]Validate(){}

    [void]Init(
    ){
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