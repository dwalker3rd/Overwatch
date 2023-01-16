param (
    [switch]$UseDefaultResponses,
    [switch]$NoNewLine
)

$product = Get-Product "BgInfo"
$Name = $product.Name 
$Publisher = $product.Publisher

$message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","PENDING$($emptyString.PadLeft(13," "))PENDING$($emptyString.PadLeft(13," "))"
Write-Host+ -NoTrace -NoTimestamp -NoSeparator -NoNewLine $message[0],$message[1] -ForegroundColor Gray,DarkGray

$sourceBgInfoConfigFile = ([FileObject]::new($Product.Config.Config))
if ($sourceBgInfoConfigFile.Exists()) {

    foreach ($node in (Get-PlatformTopology nodes -Keys)) {

        # if not installed, install BGInfo Azure VM extension
        $azVmContext = Get-AzVmContext -VmName $node
        Install-AzVmExtension -Name "BgInfo" -ResourceGroupName $azVmContext.ResourceGroupName -VmName $azVMContext.Name -Publisher "Microsoft.Compute" -ExtensionType "BgInfo" -TypeHandlerVersion "2.1"

        # create bgInfo data directory on each node
        $bgInfoDir = [DirectoryObject]::New($Product.Config.Location.Data, $node)
        $bgInfoDir.CreateDirectory()

        # copy bginfo config files to other nodes
        $destinationBgInfoConfigFile = ([FileObject]::new($Product.Config.Config, $node))
        if (!$destinationBgInfoConfigFile.Exists()) {
            Copy-Files -Path $sourceBgInfoConfigFile.Path $destinationBgInfoConfigFile.Path -Verbose:$true
        }

        # modify registry key for BGInfo Azure VM extension to use new config file
        $psSession = Use-PSSession+ -ComputerName $node
        Invoke-Command -Session $psSession -ScriptBlock { 
            $currentBgInfoRegKeyValue = (Get-ItemProperty -Path $using:Product.Config.Registry.Path -Name $using:Product.Config.Registry.Key).$($using:Product.Config.Registry.Key)
            $currentBgInfoRegKeyConfigFile = $currentBgInfoRegKeyValue.Split(" ")[1]
            $newBgInfoRegKeyValue = $currentBgInfoRegKeyValue.Replace($currentBgInfoRegKeyConfigFile,$using:destinationBgInfoConfigFile.Path)
            Set-ItemProperty -Path $using:Product.Config.Registry.Path -Name $using:Product.Config.Registry.Key -Value $newBgInfoRegKeyValue
        }

    }

    $productTask = Get-PlatformTask $global:Product.Id
    if (!$productTask) {
        Register-PlatformTask -Id $global:Product.Id -execute $pwsh -Argument "$($global:Location.Scripts)\$($global:Product.Id).ps1" -WorkingDirectory $global:Location.Scripts `
            -Once -At $(Get-Date).AddMinutes(15) -RepetitionInterval $(New-TimeSpan -Hours 1) -RepetitionDuration ([timespan]::MaxValue) -RandomDelay "PT3M" `
            -ExecutionTimeLimit $(New-TimeSpan -Minutes 10) -RunLevel Highest -Disable
        $productTask = Get-PlatformTask -Id $global:Product.Id
    }

    $message = "$($emptyString.PadLeft(40,"`b"))INSTALLED$($emptyString.PadLeft(11," "))","$($productTask.Status.ToUpper())$($emptyString.PadLeft(20-$productTask.Status.Length," "))"
    Write-Host+ -NoTrace -NoSeparator -NoTimeStamp -NoNewLine:$NoNewLine.IsPresent $message -ForegroundColor DarkGreen, ($productTask.Status -in ("Ready","Running") ? "DarkGreen" : "Red")

}
else {

    Write-Host+ -MaxBlankLines 1
    Write-Host+ -NoTrace -NoTimestamp "    Could not find the config file '$($sourceBgInfoConfigFile.Path)'." -ForegroundColor Red
    Write-Host+ -NoTrace -NoTimestamp "    Use Sysinternals BgInfo to create/save the config file '$($sourceBgInfoConfigFile.Path)'." -ForegroundColor Red

    $message = "  $Name$($emptyString.PadLeft(20-$Name.Length," "))$Publisher$($emptyString.PadLeft(20-$Publisher.Length," "))","ERROR $($emptyString.PadLeft(13," "))","PENDING$($emptyString.PadLeft(13," "))"
    Write-Host+ -NoTrace -NoTimestamp -NoSeparator $message[0],$message[1],$message[2] -ForegroundColor Gray,Red,DarkGray

}
