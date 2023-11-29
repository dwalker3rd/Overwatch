#region CLASS DEFINITIONS

using namespace System.IO

class CatalogObject {

    [ValidateNotNullOrEmpty()][string]$Type
    [ValidateNotNullOrEmpty()][string]$Id
    [string]$Name
    [string]$DisplayName
    [string]$Description
    [string]$Publisher
    [Version]$Version
    [string]$Suite
    [string]$Image
    [object]$Initialization
    [object]$Installation
    hidden [string]$SortProperty
    [bool]$Installed
    [string]$ComputerName

    CatalogObject() { $this.Init() }

    [void]Init() {
        $this.Refresh()
    }

    [void]Refresh() {
        $this.Type = $this.GetType().Name
        $this.Installed = $this.IsInstalled()
        $this.SortProperty = $this.GetSortProperty()
        $this.ComputerName = $this.ComputerName ?? $env:COMPUTERNAME
    }

    [void]Refresh([string[]]$EnvironKeyValues) {
        $this.Type = $this.GetType().Name
        $this.Installed = $this.IsInstalled($EnvironKeyValues)
        $this.SortProperty = $this.GetSortProperty()
        $this.ComputerName = $this.ComputerName ?? $env:COMPUTERNAME
    }

    [string]Uid() {
        return "$($this.Type).$($this.Id)"
    }

    [bool]IsInstalled() {
        return $this.Id -in $global:Environ.$($this.Type)
    }
    [bool]IsInstalled([string[]]$EnvironKeyValues) {
        return $this.Id -in $EnvironKeyValues
    }

    hidden [string]GetSortProperty() {
        $_typeSortOrder =  @{ CatalogObject = 0; Overwatch = 1; OS = 2; Cloud = 3; Platform = 4; Product = 5; Provider = 6; Installer = 7; Driver = 8; }
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

# move properties/members up if used in multiple class instances
# consolidate classes if possible/desired

class Overwatch : CatalogObject {

    [string]InstallPath() {
        return "$($this.Type).$($this.Id)"
    }

}

class OS : CatalogObject {}

class Cloud : CatalogObject {
    [Version]$Version
    [string]$Build
    [System.Uri]$Uri
    [string]$Log
}

class Platform : CatalogObject {
    [string]$Instance
    [Version]$Version
    [string]$Build
    [System.Uri]$Uri
    [string]$Domain
    [string]$InstallPath
    [string]$Log
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

class Installer : CatalogObject {
    [string]$Category
    [string]$SubCategory
    [string]$Log
    [object]$Config
    [System.Uri]$Uri

    [bool]IsInstalled() {
        return $this.Installed
    }
}


class Driver : CatalogObject {
    [string]$Category
    [string]$SubCategory
    [string]$DatabaseType
    [string]$DriverType
    [string]$Log
    [object]$Config
    [object]$Version
    [string]$Platform # "32-bit" or "64-bit"

    [bool]IsInstalled() {
        return $this.Installed
    }
}

class CLI : CatalogObject {
    [string]$Category
    [string]$SubCategory
    [string]$Log
    [object]$Config
    [System.Uri]$Uri

    [bool]IsInstalled() {
        return $this.Installed
    }
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

class FileObjectBase {

    [ValidateNotNullOrEmpty()]
    hidden [string]$_Path

    hidden [string]$_ComputerName

    hidden [string]$_Parent
    hidden [string]$_Root
    hidden [string]$_DirectoryName
    hidden [DirectoryInfo]$_Directory
    hidden [string]$_FullName
    hidden [string]$_Name
    hidden [string]$_Extension
    hidden [string]$_FilenameWithoutExtension
    hidden [bool]$_Exists

    FileObjectBase() {}
    FileObjectBase([string]$Path) { ([FileObjectBase]$this).Init($Path,$null,$null) }
    FileObjectBase([string]$Path,[string]$ComputerName) { ([FileObjectBase]$this).Init($Path,$ComputerName,$null) }
    FileObjectBase([string]$Path,[string]$ComputerName,[hashtable]$Options) { ([FileObjectBase]$this).Init($Path,$ComputerName,$Options) }
    
    [void] Init([string]$Path,[string]$ComputerName,[hashtable]$Options) {

        $this.ValidatePath($Path)

        if ([string]::IsNullOrEmpty($ComputerName)) {
            if ($this.IsUnc($Path)) {
                $_regexMatches = [regex]::Matches($Path,"^\\\\(.*?)\\(.*)$")
                $ComputerName = $_regexMatches.Groups[1].Value
                $Path = $_regexMatches.Groups[2].Value -replace "\$",":"
            }
            else {
                $ComputerName = $env:COMPUTERNAME.ToLower()
            }
        }

        $this.ValidateComputerName($ComputerName)

        $this._ComputerName = $ComputerName
        $this._Path = $this.IsLocal() ? $Path : $this.ToUnc($Path,$ComputerName)

        switch ($this.GetType().Name) {
            "DirectoryObject" {
                $_directoryInfo = [DirectoryInfo]::new($this._Path)
                $this._Parent = $_directoryInfo.Parent
                $this._Root = $_directoryInfo.Root
                $this._FullName = $_directoryInfo.FullName
                $this._Extension = $_directoryInfo.Extension
                $this._Name = $_directoryInfo.Name
                $this._Exists = $_directoryInfo.Exists
            }
            default {
                $_fileInfo = [fileInfo]::new($this._Path)
                $this._DirectoryName = $_fileInfo.DirectoryName
                $this._Directory = $_fileInfo.Directory
                $this._Parent = $_fileInfo.Parent
                $this._Root = $_fileInfo.Root
                $this._FullName = $_fileInfo.FullName
                $this._Extension = $_fileInfo.Extension
                $this._Name = $_fileInfo.Name
                $this._FileNameWithoutExtension = [Path]::GetFileNameWithoutExtension($this._Path)
                $this._Exists = $_fileInfo.Exists
            }
        }

    }

    [object]New(
    ) {
        if ($this.Exists) {
            Write-Warning "The file '$($this.Path)' already exists."
            return $null
        }

        $this.FileInfo = New-Item -Path $this.Path -ItemType File

        if (!$this.FileInfo) {
            Write-Warning "Unable to create '$($this.Path)'"
            return $null
        }

        return $this.FileInfo
    }
    
    [void]ValidatePath([string]$Path) {

        # valid Path format
        if (!$(Test-Path $Path -IsValid)) {
            throw "Path `'$Path`' is an invalid path specification."
        }

        # valid filename extension for this object
        if (!$this.IsDirectory($Path)) {
            $filenameExtension = [Path]::GetExtension($Path)
            if ($filenameExtension -notmatch $this.ValidFileNameExtension) {
                "Path `'$Path`' specifies an invalid filename extension for [$($this.GetType())]."
            }
        }

    }

    [void]ValidateComputerName([string]$ComputerName) {}

    # [bool]Exists() {return $this.Exists($this._Path)}
    # [bool]Exists([string]$Path) {return Test-Path $Path}
        
    [bool]IsLocal() {return $this.IsLocal($this._ComputerName)}
    [bool]IsLocal([string]$ComputerName) { return $env:COMPUTERNAME -eq $ComputerName }
    [bool]IsRemote() {return $this.IsRemote($this._ComputerName) }
    [bool]IsRemote([string]$ComputerName) {return !$this.IsLocal() }

    [bool]IsDirectory() {return $this.IsDirectory($this._Path) }
    [bool]IsDirectory([string]$Path) {return Test-Path $Path -PathType Container}
    [bool]IsDirectory([FileInfo]$_object) {return ($_object.Attributes -band [FileAttributes]::Directory) -eq [FileAttributes]::Directory}
    [bool]IsDirectory([DirectoryInfo]$_object) {return ($_object.Attributes -band [FileAttributes]::Directory) -eq [FileAttributes]::Directory}

    [bool]IsUnc() {return $this.IsUnc($this._Path)}
    [bool]IsUnc([string]$Path) {return ([Uri]$Path).IsUnc}
    
    [string]ToUnc() {return $this.ToUnc($this._Path,$this._ComputerName)}
    [string]ToUnc([string]$Path,[string]$ComputerName) {

        if ($this.IsUnc($Path)) {return $Path}
    
        $__servername = $ComputerName
        $__drive = [Path]::GetPathRoot($Path) -replace "\\",""
        $__share = $__drive -replace ":","$"
        $__directory = [Path]::GetDirectoryName($Path) -replace $__drive,"" -replace "^\\",""
        $__fileName = [Path]::GetFileName($Path)
        $__uncPath = "\\$__servername$([string]::IsNullOrEmpty($__share) ? $null : '\')$__share$([string]::IsNullOrEmpty($__directory) ? $null : '\')$__directory$([string]::IsNullOrEmpty($__filename) ? $null : '\')$__fileName"
    
        return ([Uri]($__uncPath)).IsUnc ? $__uncPath : $null

    }

}

class DirectoryObject : FileObjectBase {

    [ValidateNotNullOrEmpty()]
    [string]$Path

    [ValidateNotNullOrEmpty()]
    [string]$ComputerName

    [string]$Parent
    [string]$Root
    [string]$FullName
    [string]$Extension
    [string]$Name
    [DirectoryInfo]$DirectoryInfo
    [bool]$Exists

    DirectoryObject() : base() {}
    DirectoryObject([string]$Path) : base($Path) {
        ([DirectoryObject]$this).Init($null)
    }
    DirectoryObject([string]$Path,[hashtable]$Options) : base($Path) {
        ([DirectoryObject]$this).Init($Options)
    }
    DirectoryObject([string]$Path,[string]$ComputerName) : base($Path,$ComputerName) {
        ([DirectoryObject]$this).Init($null)
    }
    DirectoryObject([string]$Path,[string]$ComputerName,[hashtable]$Options) : base($Path,$ComputerName) {
        ([DirectoryObject]$this).Init($Options)
    }
    
    [void]Init([hashtable]$Options) {

        $this.Path = $this._Path
        $this.ComputerName = $this._ComputerName
        $this.Parent = $this._Parent
        $this.Root = $this._Root
        $this.FullName = $this._FullName
        $this.Extension = $this._Extension
        $this.Name = $this._Name
        $this.DirectoryInfo = Get-Item -Path $this._Path -ErrorAction SilentlyContinue
        $this.Exists = $this._Exists

    }

    [System.Security.AccessControl.DirectorySecurity]GetAcl() { return Get-Acl -Path $this.Path }

    [System.Security.AccessControl.DirectorySecurity]SetAcl(
        [string]$IdentityReference,
        [System.Security.AccessControl.FileSystemRights]$FileSystemRights,
        [System.Security.AccessControl.AccessControlType]$AccessControlType
        )
    {
        $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
        $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None
        return $this.SetAcl($IdentityReference,$FileSystemRights,$InheritanceFlags,$PropagationFlags,$AccessControlType)
    }
    
    [System.Security.AccessControl.DirectorySecurity]SetAcl(
        [string]$IdentityReference,
        [System.Security.AccessControl.FileSystemRights]$FileSystemRights,
        [System.Security.AccessControl.InheritanceFlags]$InheritanceFlags,
        [System.Security.AccessControl.PropagationFlags]$PropagationFlags,
        [System.Security.AccessControl.AccessControlType]$AccessControlType
        )
    {
        $acl = $this.GetAcl()
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($IdentityReference, $FileSystemRights, $InheritanceFlags, $PropagationFlags, $AccessControlType)
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $this.Path -AclObject $acl
        return $this.GetAcl()
    }

    [System.Security.AccessControl.DirectorySecurity]SetAcl([object]$Acl) {
        Set-Acl -Path $this.Path -AclObject $Acl
        return $this.GetAcl()
    }

    [System.Security.AccessControl.DirectorySecurity]RemoveAcl([string]$IdentityReference) {
        $acl = $this.GetAcl()
        $accessRuleToRemove = $acl.Access | Where-Object {$_.IdentityReference -eq $IdentityReference}
        if ($accessRuleToRemove) { $acl.RemoveAccessRule($accessRuleToRemove) }
        return $this.SetAcl($acl)
    }

}

class FileObject : FileObjectBase {

    [ValidateNotNullOrEmpty()]
    [string]$Path

    [ValidateNotNullOrEmpty()]
    [string]$ComputerName

    [string]$DirectoryName
    [DirectoryInfo]$Directory
    [string]$FullName
    [string]$Extension
    [string]$Name
    [string]$FilenameWithoutExtension
    [object]$FileInfo
    [bool]$Exists

    hidden [string]$ValidFileNameExtension = "(?:\..+)?$"

    FileObject() : base() {}
    FileObject([string]$Path) : base($Path) {
        ([FileObject]$this).Init($null)
    }
    FileObject([string]$Path,[hashtable]$Options) : base($Path) {
        ([FileObject]$this).Init($Options)
    }
    FileObject([string]$Path,[string]$ComputerName) : base($Path,$ComputerName) {
        ([FileObject]$this).Init($null)
    }
    FileObject([string]$Path,[string]$ComputerName,[hashtable]$Options) : base($Path,$ComputerName) {
        ([FileObject]$this).Init($Options)
    }

    [void]Init([hashtable]$Options) {

        $this.Path = $this._Path
        $this.ComputerName = $this._ComputerName
        $this.FullName = $this._FullName
        $this.DirectoryName = $this._DirectoryName
        $this.Directory = $this._Directory
        $this.Extension = $this._Extension
        $this.Name = $this._Name
        $this.FilenameWithoutExtension = $this._FileNameWithoutExtension
        if ($this.IsDirectory()) {
            $this.FileInfo = Get-ChildItem -Path $this.Path @Options -ErrorAction SilentlyContinue
        }
        else {
            $this.FileInfo = Get-Item -Path $this.Path -ErrorAction SilentlyContinue
        }
        $this.Exists = $this._Exists

    }

    [System.Security.AccessControl.FileSecurity]GetAcl() { return Get-Acl -Path $this.Path }

    [System.Security.AccessControl.FileSecurity]SetAcl(
        [string]$IdentityReference,
        [System.Security.AccessControl.FileSystemRights]$FileSystemRights,
        [System.Security.AccessControl.AccessControlType]$AccessControlType
        )
    {
        $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::None
        $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None
        return $this.SetAcl($IdentityReference,$FileSystemRights,$InheritanceFlags,$PropagationFlags,$AccessControlType)
    }    
    
    [System.Security.AccessControl.FileSecurity]SetAcl(
        [string]$IdentityReference,
        [System.Security.AccessControl.FileSystemRights]$FileSystemRights,
        [System.Security.AccessControl.InheritanceFlags]$InheritanceFlags,
        [System.Security.AccessControl.PropagationFlags]$PropagationFlags,
        [System.Security.AccessControl.AccessControlType]$AccessControlType
    )
    {
        $acl = $this.GetAcl()
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($IdentityReference, $FileSystemRights, $InheritanceFlags, $PropagationFlags, $AccessControlType)
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $this.Path -AclObject $acl
        return $this.GetAcl()
    }  

    [System.Security.AccessControl.FileSecurity]SetAcl([object]$Acl) {
        Set-Acl -Path $this.Path -AclObject $Acl
        return $this.GetAcl()
    }

    [System.Security.AccessControl.FileSecurity]RemoveAcl([string]$IdentityReference) {
        $acl = $this.GetAcl()
        $accessRuleToRemove = $acl.Access | Where-Object {$_.IdentityReference -eq $IdentityReference}
        if ($accessRuleToRemove) { $acl.RemoveAccessRule($accessRuleToRemove) }
        return $this.SetAcl($acl)
    }

}

class LogObject : FileObject {

    [string]$Name

    hidden [string]$ValidFileNameExtension = "^\.log$"

    LogObject() : base() {}
    LogObject([string]$Path) : base($Path) {}
    LogObject([string]$Path,[string]$ComputerName) : base($Path,$ComputerName) {}
    LogObject([string]$Path,[string]$ComputerName,[hashtable]$Options) : base($Path,$ComputerName,$Options) {}

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

    CacheObject() : base() {}
    CacheObject([string]$Path) : base($Path) {
        $this.Init($Path,$env:COMPUTERNAME,[timespan]::MaxValue,$null)
    }
    CacheObject([string]$Path,[string]$ComputerName) : base($Path,$ComputerName) {
        $this.Init($Path,$ComputerName,[timespan]::MaxValue,$null)
    }
    CacheObject([string]$Path,[string]$ComputerName,[timespan]$MaxAge) : base($Path,$ComputerName) {
        $this.Init($Path,$ComputerName,$MaxAge,$null)
    }
    CacheObject([string]$Path,[string]$ComputerName,[hashtable]$Options) : base($Path,$ComputerName,$Options) {
        $this.Init($Path,$ComputerName,[timespan]::MaxValue,$Options)
    }  
    CacheObject([string]$Path,[string]$ComputerName,[timespan]$MaxAge,[hashtable]$Options) : base($Path,$ComputerName,$Options) {
        $this.Init($Path,$ComputerName,$MaxAge,$Options)
    }          

    [void] Init([string]$Path,[string]$ComputerName,[timespan]$MaxAge,[hashtable]$Options) {

        $this.MaxAge = $MaxAge

    }

    [timespan]Age() {return $this.FileInfo.LastWriteTime ? [datetime]::Now - $this.FileInfo.LastWriteTime : $null}
    [bool]Expired() {return $this.Age() -gt $this.MaxAge}
    [bool]Expired([timespan]$MaxAge) {return $this.Age() -gt $MaxAge}
}

class VaultObject : FileObject {
    
    [string]$Name

    hidden [string]$ValidFileNameExtension = "^\.vault$"

    VaultObject() : base() {}
    VaultObject([string]$Path) : base($Path) {}
    VaultObject([string]$Path,[hashtable]$Options) : base($Path,$Options) {} 
    VaultObject([string]$Path,[string]$ComputerName) : base($Path,$ComputerName) {}      
    VaultObject([string]$Path,[string]$ComputerName,[hashtable]$Options) : base($Path,$ComputerName,$Options) {}     
    
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