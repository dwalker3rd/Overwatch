    function global:Get-Files {

        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$false,Position=0)][string[]]$Path = $($(Get-Location).Path),
            [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
            [Parameter(Mandatory=$false)][string]$Filter,
            [switch]$Recurse,
            [Parameter(Mandatory=$false)][string]$View
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"

        $params = @{}
        if ($Filter) {$params += @{Filter = $Filter}}
        if ($Recurse) {$params += @{Recurse = $true}}

        $files = @()
        foreach ($node in $ComputerName) {
            $files += ([FileObject]::new($Path, $node, $params))
        } 

        return $files | Select-Object -Property $($View ? $FileObjectView.$($View) : $FileObjectView.Default)

    }

    function global:Remove-Files {

        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$false,Position=0)][string[]]$Path = $($(Get-Location).Path),
            [Parameter(Mandatory=$false)][string[]]$ComputerName = $env:COMPUTERNAME,
            [Parameter(Mandatory=$false)][string]$Filter,
            [Parameter(Mandatory=$false)][int]$Keep=0,
            [switch]$Days,
            [switch]$Recurse,
            [switch]$Force
        )

        Write-Debug "[$([datetime]::Now)] $($MyInvocation.MyCommand)"
        
        $purgeArguments = @{}
        # if ($Filter) {$purgeArguments += @{Filter = $Filter}}
        if ($Force) {$purgeArguments += @{Force = $Force}}
        if ($Recurse) {$purgeArguments += @{Recurse = $Recurse}}   

        $files = Get-Files -Path $Path -Filter $Filter -ComputerName $ComputerName
        
        foreach ($f in $files) {
            if ($Days) {
                $f.fileInfo = $f.fileInfo | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-$Keep)}}
            else {
                $f.fileInfo = $f.fileInfo | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip $Keep} 
            
            if ($f.fileInfo) {
                # $f.Remove();
                Write-Verbose "$($f.fileInfo.FullName)"
                Remove-Item $f.fileInfo.FullName @purgeArguments
            }
        }

        return #$files | Where-Object {$_.fileInfo}
    }

    function global:Copy-Files {

        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$true,Position=0)][string]$Path,
            [Parameter(Mandatory=$false,Position=1)][string]$Destination,
            [Parameter(Mandatory=$false)][string[]]$ComputerName,
            [Parameter(Mandatory=$false)][string[]]$ExcludeComputerName=$env:COMPUTERNAME
        )
    
        foreach ($node in $ComputerName) {

            if ($ExcludeComputerName -notcontains $node.ToUpper()) {

                $files = Get-ChildItem $Path

                foreach ($file in $files) {

                    $Destination = ([string]::IsNullOrEmpty($Destination) ? $file.FullName : $Destination).Replace(":","$")

                    Copy-Item -Path $file.FullName -Destination "\\$node\$Destination"

                    Write-Host+ -NoTrace -NoSeparator -IfVerbose "Copy-Item -Path ",$file," -Destination ",$Destination -ForegroundColor DarkGray,Gray,DarkGray,Gray

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