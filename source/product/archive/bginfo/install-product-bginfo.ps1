param (
    [switch]$UseDefaultResponses
)

$definitionsPath = $global:Location.Definitions
. $definitionsPath\classes.ps1

$_product = Get-Product "BgInfo" -NoCache
$_product | Out-Null

# create bgInfo data directory on local node
$bgInfoDir = [DirectoryObject]::New($_product.Config.Location.Data)
$bgInfoDir.CreateDirectory()

$sourceBgInfoConfigFile = $_product.Config.Location.Files.Source.ConfigBgi
if (Test-Path $sourceBgInfoConfigFile) {

    foreach ($node in (Get-PlatformTopology nodes -Keys)) {

        # if not installed, install BGInfo Azure VM extension
        $azVmContext = Get-AzVmContext -VmName $node
        Install-AzVmExtension -Name "BgInfo" -ResourceGroupName $azVmContext.ResourceGroupName -VmName $azVMContext.Name `
            -Publisher $_product.Config.Extension.Publisher -ExtensionType $_product.Config.Extension.ExtensionType -TypeHandlerVersion $_product.Config.Extension.TypeHandlerVersion

        # create bgInfo data directory on each node
        $bgInfoDir = [DirectoryObject]::New($_product.Config.Location.Data, $node)
        $bgInfoDir.CreateDirectory()

        # copy bginfo config files to VmExtension directory on other nodes
        $destinationBgInfoConfigFile = $_product.Config.Location.Files.Destination.ConfigBgi
        Copy-Files -Path $sourceBgInfoConfigFile $destinationBgInfoConfigFile -ComputerName $node -Overwrite -Quiet

        # # copy bginfo config files to Overwatch directory on other nodes
        # $destinationBgInfoConfigFile = $_product.Config.Files.BgInfoBgi
        # if (!$destinationBgInfoConfigFile.Exists) {
        #     Copy-Files -Path $sourceBgInfoConfigFile $destinationBgInfoConfigFile -ComputerName $node -Verbose:$true
        # }

        # modify registry key for BGInfo Azure VM extension to use new config file
        $psSession = Use-PSSession+ -ComputerName $node
        Invoke-Command -Session $psSession -ScriptBlock { 
            $currentBgInfoRegKeyValue = (Get-ItemProperty -Path $using:_product.Config.Registry.Path -Name $using:_product.Config.Registry.Key).$($using:_product.Config.Registry.Key)
            $currentBgInfoRegKeyConfigFile = $currentBgInfoRegKeyValue.Split(" ")[1]
            $newBgInfoRegKeyValue = $currentBgInfoRegKeyValue.Replace($currentBgInfoRegKeyConfigFile,$using:destinationBgInfoConfigFile)
            Set-ItemProperty -Path $using:_product.Config.Registry.Path -Name $using:_product.Config.Registry.Key -Value $newBgInfoRegKeyValue
        }

    }

    $productTask = Get-PlatformTask $_product.Id
    if (!$productTask) {
        Register-PlatformTask -Id $_product.Id -execute $pwsh -Argument "$($global:Location.Scripts)\$($_product.Id).ps1" -WorkingDirectory $global:Location.Scripts `
            -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Hours 1) -RandomDelay $(New-TimeSpan -Minutes 3) `
            -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
        $productTask = Get-PlatformTask -Id $_product.Id
    }

}
else {

    Write-Host+ # end previous -NoNewLine
    Write-Host+
    Write-Host+ -NoTimestamp -Indent 4 "Could not find the config file `'$sourceBgInfoConfigFile`'." -ForegroundColor Red
    Write-Host+ -NoTimestamp -Indent 4 "Use command alias `'bgInfoExe`' to create/save a new configuration file, then re-install BgInfo." -ForegroundColor Red
    Write-Host+

    Uninstall-CatalogObject -Type Product -Id $_product.Id -DeleteAllData -Force -Quiet

}

function global:Invoke-BgInfoCommandLine {

    param(
        [Parameter(Mandatory=$false,Position=0)][string]$ConfigurationFile = $global:Product.Config.Location.Files.Destination.ConfigCgi
    )

    $_product = Get-Product BgInfo -NoCache
    $_expression = ". "
    $_expression += $_product ? $_product.Config.CommandLine.Executable : "C:\Packages\Plugins\Microsoft.Compute.BGInfo\2.1\bgInfo.exe"
    $_expression += ![string]::IsNullOrEmpty($ConfigurationFile) ? " $ConfigurationFile" : ""
    $_expression += " /NOLICPROMPT"
    Invoke-Expression $_expression

}
Set-Alias -Name bgInfoExe -Value Invoke-BgInfoCommandLine -Scope Global
