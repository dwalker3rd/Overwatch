$global:rmtAdmin = "$($global:Platform.InstallPath)\$global:RMTControllerAlias\rmtAdmin"

#region DATABASE

    function global:Query-RMTDatabase {

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string]$Sql
        )

        $prerequisiteTestResults = Test-Prerequisites -Type "Platform" -Id "TableauRMT" -PrerequisiteType Initialization -Quiet
        $postgresqlPrerequisiteTestResult = $prerequisiteTestResults.Prerequisites | Where-Object {$_.id -eq "TableauResourceMonitoringToolPostgreSQL"}
        if (!$postgresqlPrerequisiteTestResult.Pass) { 
            Write-Log -Action "PrerequisiteTest" -Target "$($postgresqlPrerequisiteTestResult.Type)\$($postgresqlPrerequisiteTestResult.Id)" -EntryType Warning -Status $postgresqlPrerequisiteTestResult.Status -Force
            throw "The $($postgresqlPrerequisiteTestResult.Id) $($postgresqlPrerequisiteTestResult.Type) is $($postgresqlPrerequisiteTestResult.Status.ToUpper())"
        }

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

    function script:Get-RMTRole {

        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$false,Position=0)][string[]]$ComputerName = $env:COMPUTERNAME
        )

        if ($ComputerName -in (pt components.controller.nodes -k)) {return "Controller"}
        if ($ComputerName -in (pt components.agents.nodes -k)) {return "Agent"}

        throw "Node `"$ComputerName`" is not part of this platform's topology."

    }

    function global:Get-RMTController {

        [CmdletBinding()]
        param (
            [switch]$Quiet
        )

        $message = "<Tableau RMT Controller <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $version = Get-RMTVersion
        if (!$version) {
            if ($(Get-Cache platforminfo).Exists) {
                $version = Read-Cache platforminfo | Where-Object {$_.Role -eq "Controller"}
            }
        }
        
        $controller = [PSCustomObject]@{
            IsOK = $true
            RollupStatus = ""
            Name = [string]$global:PlatformTopologyBase.Components.Controller.Nodes.Keys
            BuildVersion = $version.BuildVersion
            InfoVersion = $version.InfoVersion
            ProductVersion = $version.ProductVersion
            Services = @()
        }
        $controller.Services = Get-PlatformServices -ComputerName $controller.Name

        $controller.RollupStatus = $controller.Services.Status | Sort-Object -Unique
        if ($controller.RollupStatus -notin ("Running","Stopped")) {
            $controller.RollupStatus = "Degraded"
        }
        $controller.IsOK = $controller.RollupStatus -eq "Running"

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp -NoNewLine $message -ForegroundColor DarkGreen 
        $message = "/",$controller.RollupStatus.ToUpper()
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGray,($controller.IsOK ? "DarkGreen" : "Red")

        return $controller

    }
    Set-Alias -Name rmtController -Value Get-RMTController -Scope Global
    
    function global:Get-RMTAgent {
        
        [CmdletBinding(DefaultParameterSetName="AllAgents")]
        param(
            [Parameter(Mandatory=$false,ParameterSetName="ByEnvironment")][string]$EnvironmentIdentifier,
            [Parameter(Mandatory=$false,ParameterSetName="ByAgent")][string]$Agent,

            [Parameter(Mandatory=$false,ParameterSetName="AllAgents")]
            [Parameter(Mandatory=$false,ParameterSetName="ByEnvironment")]
            [Parameter(Mandatory=$false,ParameterSetName="ByAgent")]
            [switch]$Quiet
        )

        $message = "<Tableau RMT Agents <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $sql = "select public.agent.*,public.serverenvironment.\`"Identifier\`" as \`"EnvironmentIdentifier\`" from public.agent " +
                    " join public.server on public.agent.\`"ServerId\`" = public.server.\`"Id\`" " + 
                    " join public.serverenvironment on public.server.\`"ServerEnvironmentId\`" = public.serverenvironment.\`"Id\`""
        if ($EnvironmentIdentifier) {
            $sql += " where LOWER(public.serverenvironment.\`"Identifier\`") = '$($EnvironmentIdentifier.ToLower())'"
        }
        if ($Agent) {
            $sql += " where LOWER(public.agent.\`"Name\`") = '$($Agent.ToLower())'"
        }

        try {
            $agents = Query-RMTDatabase $sql
        }
        catch {
            Write-Host+ -Iff (!$Quiet)
            Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkYellow
            Write-Host+ -NoTrace "Unable to query the RMT database for version information" -ForegroundColor DarkYellow

            $message = "<Tableau RMT Environments <.>48> FAIL"
            Write-Host+ -Iff (!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkRed

            return
        }       
        
        if (!$agents) {
            if ($EnvironmentIdentifier) {
                throw "No environment found with the name '$($EnvironmentIdentifier)'"
            }
            if ($Agent) {
                throw "No agent found with the name '$($Agent)'"
            }
            throw "No agents found"
        }    

        foreach ($_agent in $agents) {
            $_agent.Name = $_agent.Name.ToLower()
            $_agent | Add-Member -NotePropertyName "Services" -NotePropertyValue @{}
            $_agent.Services = Get-PlatformServices -ComputerName $_agent.Name
        }            
        
        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen        

        return $agents | Sort-Object -Property Name

    }
    Set-Alias -Name rmtAgent -Value Get-RMTAgent -Scope Global

    function global:Get-RMTEnvironment {
        
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false,Position=0)][string]$EnvironmentIdentifier,
            [switch]$Quiet
        )

        $message = "<Tableau RMT Environments <.>48> PENDING"
        Write-Host+ -Iff (!$Quiet) -NoTrace -NoNewLine -Parse $message -ForegroundColor Gray,DarkGray,DarkGray

        $sql = "select * from public.serverenvironment"
        if ($EnvironmentIdentifier) {
            $sql += " where public.serverenvironment.\`"Identifier\`" = '$EnvironmentIdentifier'"
        }

        try {
            $rmtEnviron = Query-RMTDatabase $sql
        }
        catch {
            Write-Host+ -Iff (!$Quiet)
            Write-Host+ -NoTrace $_.Exception.Message -ForegroundColor DarkYellow
            Write-Host+ -NoTrace "Unable to query the RMT database for version information" -ForegroundColor DarkYellow

            $message = "<Tableau RMT Environments <.>48> FAIL"
            Write-Host+ -Iff (!$Quiet) -NoTrace -Parse $message -ForegroundColor Gray,DarkGray,DarkRed

            return
        }

        if (!$rmtEnviron) {
            throw "No such environment `"$EnvironmentIdentifier`"."
        }

        $message = "$($emptyString.PadLeft(8,"`b")) SUCCESS"
        Write-Host+ -Iff (!$Quiet)  -NoTrace -NoSeparator -NoTimestamp $message -ForegroundColor DarkGreen        

        return $rmtEnviron

    }
    Set-Alias -Name rmtEnvirons -Value Get-RMTEnvironment -Scope Global

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

        try {
            $versions = Query-RMTDatabase $sql
        }
        catch {
            return
        }

        return [PSCustomObject]@{
            Node = $ComputerName.ToLower()
            Role = $role
            ProductVersion = $versions.ProductVersion
            BuildVersion = $versions.BuildVersion
            InfoVersion = $versions.InfoVersion
        }

    }
    Set-Alias -Name rmtVersion -Value Get-RMTVersion -Scope Global