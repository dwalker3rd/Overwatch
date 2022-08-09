function global:Install-PythonPackage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string[]]$Package,
        [Parameter(Mandatory=$true)][string]$Pip,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME,
        [switch]$Quiet
    )

    if (!$Pip.toLower().EndsWith('\pip')) {$Pip += '\pip'}

    $psSessions = Get-PSSession+ -ComputerName $ComputerName

    foreach ($psSession in $psSessions) {
        Write-Host+ -Iff (!$Quiet) -MaxBlankLines 1
        $message = "Installing Python Package[s] on $($psSession.ComputerName)"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp $message
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp $emptyString.PadLeft($message.Length,"-")
        if ($Quiet) { 
            Invoke-Command -Session $psSession { . $using:Pip install $using:Package | Out-Null }
        }
        else {
            Invoke-Command -Session $psSession { . $using:Pip install $using:Package }
        }
    }
    Write-Host+ -Iff (!$Quiet)

    Remove-PSSession $psSession

    return

}

function global:Uninstall-PythonPackage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][string[]]$Package,
        [Parameter(Mandatory=$true)][string]$Pip,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME,
        [switch]$Quiet
    )

    if (!$Pip.toLower().EndsWith('\pip')) {$Pip += '\pip'}

    $psSessions = Get-PSSession+ -ComputerName $ComputerName

    foreach ($psSession in $psSessions) {
        Write-Host+ -Iff (!$Quiet) -MaxBlankLines 1
        $message = "Uninstalling Python Package[s] on $($psSession.ComputerName)"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp $message
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoTimestamp $emptyString.PadLeft($message.Length,"-")
        if ($Quiet) { 
            Invoke-Command -Session $psSession { . $using:Pip uninstall $using:Package --yes | Out-Null }
        }
        else {
            Invoke-Command -Session $psSession { . $using:Pip uninstall $using:Package --yes }
        }
    }
    Write-Host+ -Iff (!$Quiet)

    Remove-PSSession $psSession

    return

}

function global:Get-PythonPackage {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)][object[]]$Package,
        [Parameter(Mandatory=$true)][string]$Pip,
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME
    )

    if (!$Pip.toLower().EndsWith('\pip')) {$Pip += '\pip'}

    $psSession = Get-PSSession+ -ComputerName $ComputerName

    $results = @()
    $results += Invoke-Command -Session $psSession {
        (. $using:Pip list --format=json | ConvertFrom-Json) | Where-Object {$_.name -in $using:Package}
    }

    Remove-PSSession $psSession

    return $results | Select-Object -Property @{Name='ComputerName';Expression={$_.PSComputerName.ToLower()}}, @{Name='Name';Expression={$_.name}}, @{Name='Version';Expression={$_.version}} | Sort-Object -Property ComputerName, Name

}

function global:Repair-PythonSSL {

    # see https://github.com/conda/conda/issues/8273

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)][string[]]$ComputerName=$env:COMPUTERNAME
    )

    $dlls = @(
        "libcrypto-1_1-x64.dll",
        "libssl-1_1-x64.dll"
    )
    $from = "$($global:Platform.InstallPath)\bin\Miniconda3\envs\DesignerBaseTools_vEnv\Library\bin"
    $to = "$($global:Platform.InstallPath)\bin\Miniconda3\envs\DesignerBaseTools_vEnv\DLLs"

    foreach ($node in $ComputerName) {
        Write-Host+ -NoTrace "$node" -ForegroundColor DarkBlue -IfVerbose
        foreach ($dll in $dlls) {
            $message = "  $dll"
            Write-Host+ -NoTrace -NoNewLine $message,(Format-Leader -Length 35 -Adjust $message.Length) -ForegroundColor Gray,DarkGray -NoSeparator -IfVerbose
            if (!([System.IO.File]::Exists("\\$node\$($to.replace(":","`$"))\$dll"))) {
                Write-Host+ -NoTrace -NoTimeStamp " MISSING" -ForegroundColor DarkRed -IfVerbose
                $message = "  Copying dll : OK"
                Write-Host+ -NoTrace $message.Split(":",2)[0],(Format-Leader -Length 25 -Adjust (($message.Split(":",2)[0]).Length)),$message.Split(":",2)[1] -ForegroundColor Gray,DarkGray,DarkGreen -IfVerbose
                Copy-Files -Path "$from\$dll" -Destination "$to\$dll" -ComputerName $node -ExcludeComputerName $env:COMPUTERNAME
            }
            else {
                Write-Host+ -NoTrace -NoTimestamp " OK" -ForegroundColor DarkGreen -IfVerbose
            }
        }
    }

    Write-Host+ -IfVerbose

}