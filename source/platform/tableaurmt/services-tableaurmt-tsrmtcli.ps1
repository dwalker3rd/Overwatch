$global:rmtAdmin = "$($global:Platform.InstallPath)\$global:RMTControllerAlias\rmtAdmin"

#region DATABASE

    function global:Query-RMTDatabase {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string]$Sql
        )

        $queryTimeout = 10

        $guid = [guid]::NewGuid()
        $guidDirectory = New-Item -Path $global:Location.Data -Name $guid -ItemType "directory"
        $destinationPath = "$($global:Location.Data)\$guid"
        $outFile = "$destinationPath\queryresults.zip"
        $queryResults = "$($destinationPath)\results-1.csv"

        $obj = $null
        try {
            . $rmtAdmin query $Sql --outfile=$outFile --force --timeout=$queryTimeout | Out-Null
            Expand-Archive $outFile -DestinationPath $destinationPath
            $obj = Import-Csv $queryResults
        }
        catch {
        }
        finally {
            Remove-Item $guidDirectory -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }

        return $obj

    }
    Set-Alias -Name rmtQuery -Value Query-RMTDatabase -Scope Global

#endregion DATABASE
#region TOPOLOGY

    function global:Get-RMTController {

        [CmdletBinding()]
        param (
            [switch]$Quiet
        )

        $message = "<Tableau RMT Controller <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $version = Get-RMTVersion

        $controller = [PSCustomObject]@{
            IsOK = $true
            RollupStatus = ""
            Name = [string]$global:PlatformTopologyBase.Components.Controller.Nodes.Keys
            BuildVersion = $version.buildVersion
            InfoVersion = $version.infoVersion
            ProductVersion = $version.productVersion
            Services = @()
        }
        $controller.Services = Get-PlatformServices -ComputerName $controller.Name

        $controller.RollupStatus = $controller.Services.Status | Sort-Object -Unique
        if ($controller.RollupStatus -notin ("Running","Stopped")) {
            $controller.RollupStatus = "Degraded"
        }
        $controller.IsOK = $controller.RollupStatus -eq "Running"

        $message = "$($emptyString.PadLeft(10,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen 
        $message = "/",$controller.RollupStatus.ToUpper()
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,($controller.IsOK ? "DarkGreen" : "Red")

        return $controller

    }
    Set-Alias -Name rmtController -Value Get-RMTController -Scope Global
    
    function global:Get-RMTAgent {
        
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false)][string]$EnvironmentIdentifier,
            [Parameter(Mandatory=$false)][object]$Controller,
            [switch]$Quiet
        )

        if (!$Controller) {$Controller = Get-RMTController -Quiet}

        $message = "<Tableau RMT Agents <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        if (!$Controller.IsOK) {
            $message = "$($emptyString.PadLeft(10,"`b")) FAILURE"
            Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red
            return
        }

        $sql = "select public.agent.*,public.serverenvironment.\`"Identifier\`" as \`"EnvironmentIdentifier\`" from public.agent " +
                    " join public.server on public.agent.\`"ServerId\`" = public.server.\`"Id\`" " + 
                    " join public.serverenvironment on public.server.\`"ServerEnvironmentId\`" = public.serverenvironment.\`"Id\`""
        if ($EnvironmentIdentifier) {
            $sql += " where public.serverenvironment.\`"Identifier\`" = '$EnvironmentIdentifier'"
        }
        
        $agents = Query-RMTDatabase $sql

        if (!$agents) {
            throw "No such environment `"$EnvironmentIdentifier`"."
        }

        foreach ($agent in $agents) {
            $agent.Name = $agent.Name.ToLower()
            $agent | Add-Member -NotePropertyName "Services" -NotePropertyValue @{}
            $agent.Services = Get-PlatformServices -ComputerName $agent.Name
        }

        $message = "$($emptyString.PadLeft(10,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

        return $agents | Sort-Object -Property Name

    }
    Set-Alias -Name rmtAgent -Value Get-RMTAgent -Scope Global

    function global:Get-RMTEnvironments {
        
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$EnvironmentIdentifier,
            [Parameter(Mandatory=$false)][object]$Controller,
            [switch]$Quiet
        )

        if (!$Controller) {$Controller = Get-RMTController -Quiet}

        $message = "<Tableau RMT Environments <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        if (!$Controller.IsOK) {
            $message = "$($emptyString.PadLeft(10,"`b")) FAILURE"
            Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor Red
            return
        }

        $sql = "select * from public.serverenvironment"
        if ($EnvironmentIdentifier) {
            $sql += " where public.serverenvironment.\`"Identifier\`" = '$EnvironmentIdentifier'"
        }
        $environ = Query-RMTDatabase $sql

        if (!$environ) {
            throw "No such environment `"$EnvironmentIdentifier`"."
        }

        $message = "$($emptyString.PadLeft(10,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen

        return $environ

    }
    Set-Alias -Name rmtEnvirons -Value Get-RMTEnvironments -Scope Global

    function global:Get-RMTVersion {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = $env:COMPUTERNAME
        )

        $role = Get-RMTRole $ComputerName

        switch ($role) {
            "Controller" {
                $infoVersion = (. $rmtAdmin version)[1]
                $sql = "select \`"ProductVersion\`",\`"BuildVersion\`",\`"InfoVersion\`" from public.upgradehistory where public.upgradehistory.\`"InfoVersion\`" = '$infoVersion'"
            }
            "Agent" {
                $sql = "select \`"ProductVersion\`",\`"BuildVersion\`",\`"InfoVersion\`" from public.agent where public.agent.\`"Name\`" = '$($ComputerName.ToUpper())'"
            }
        }
        $versions = Query-RMTDatabase $sql
        return [PSCustomObject]@{
            Node = $ComputerName.ToLower()
            Role = $role
            ProductVersion = $versions.ProductVersion
            BuildVersion = $versions.BuildVersion
            InfoVersion = $versions.InfoVersion
        }

    }
    Set-Alias -Name rmtVersion -Value Get-RMTVersion -Scope Global