Write-Host+

$overwatchRoot = $global:Location.Root
$operatingSystemId = $global:Environ.OS
$cloudId = $global:Environ.Cloud
$platformId = $global:Environ.Platform
$platformInstanceId = $global:Environ.Instance

$updatedFiles = @()

#region CORE

    $coreFiles = @()

    $files = (Get-ChildItem $overwatchRoot\source\core -File).VersionInfo.FileName
    foreach ($file in $files) { 
        $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
        if ($coreFile) {
            $coreFiles += $coreFile
        }
    }

    $files = (Get-ChildItem $overwatchRoot\source\core\config -File).VersionInfo.FileName
    foreach ($file in $files) { 
        $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
        if ($coreFile) {
            $coreFiles += $coreFile
        }
    }

    $files = (Get-ChildItem $overwatchRoot\source\core\definitions -File).VersionInfo.FileName
    foreach ($file in $files) { 
        $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
        if ($coreFile) {
            $coreFiles += $coreFile
        }
    }

    $files = (Get-ChildItem $overwatchRoot\source\core\services -File -Recurse).VersionInfo.FileName
    foreach ($file in $files) { 
        $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
        if ($coreFile) {
            $coreFiles += $coreFile
        }
    }
    $files = (Get-ChildItem $overwatchRoot\source\core\views -File -Recurse).VersionInfo.FileName
    foreach ($file in $files) { 
        $coreFile = Copy-File $file $file.replace("\source\core","") -WhatIf
        if ($coreFile) {
            $coreFiles += $coreFile
        }
    }

    $updatedfiles += $coreFiles

#endregion CORE
#region CLOUD

    $cloudFiles = @()
    $cloudFiles += Copy-File $overwatchRoot\source\cloud\$($cloudId.ToLower())\definitions-cloud-$($cloudId.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-cloud-$($cloudId.ToLower()).ps1 -WhatIf
    $cloudFiles += Copy-File $overwatchRoot\source\cloud\$($cloudId.ToLower())\services-$($cloudId.ToLower())*.ps1 $overwatchRoot\services -WhatIf
    $cloudFiles += Copy-File $overwatchRoot\source\cloud\$($cloudId.ToLower())\install-cloud-$($cloudId.ToLower()).ps1 $overwatchRoot\install\install-cloud-$($cloudId.ToLower()).ps1 -WhatIf
    $cloudFiles += Copy-File $overwatchRoot\source\cloud\$($cloudId.ToLower())\config-cloud-$($cloudId.ToLower())-template.ps1 $overwatchRoot\config\config-cloud-$($cloudId.ToLower()).ps1 -WhatIf
    $cloudFiles += Copy-File $overwatchRoot\source\cloud\$($cloudId.ToLower())\initialize-cloud-$($cloudId.ToLower())-template.ps1 $overwatchRoot\initialize\initialize-cloud-$($cloudId.ToLower()).ps1 -WhatIf
    $updatedFiles += $cloudFiles

#endregion CLOUD
#region OS

    $osFiles = @()
    $osFiles += Copy-File $overwatchRoot\source\os\$($operatingSystemId.ToLower())\definitions-os-$($operatingSystemId.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
    $osFiles += Copy-File $overwatchRoot\source\os\$($operatingSystemId.ToLower())\services-$($operatingSystemId.ToLower())*.ps1 $overwatchRoot\services -WhatIf
    $osFiles += Copy-File $overwatchRoot\source\os\$($operatingSystemId.ToLower())\config-os-$($operatingSystemId.ToLower())-template.ps1 $overwatchRoot\config\config-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
    $osFiles += Copy-File $overwatchRoot\source\os\$($operatingSystemId.ToLower())\initialize-os-$($operatingSystemId.ToLower())-template.ps1 $overwatchRoot\initialize\initialize-os-$($operatingSystemId.ToLower()).ps1 -WhatIf
    $updatedFiles += $osFiles

#endregion OS
#region PLATFORM            

    $platformFiles = @()
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\definitions-platform-$($platformId.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-platform-$($platformId.ToLower()).ps1 -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\definitions-platforminstance-$($platformId.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-platforminstance-$($platformInstanceId.ToLower()).ps1 -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\services-$($platformId.ToLower())*.ps1 $overwatchRoot\services -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformId.ToLower())-template.ps1 $overwatchRoot\config\config-platform-$($platformId.ToLower()).ps1 -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\config-platform-$($platformInstanceId)-template.ps1 $overwatchRoot\config\config-platform-$($platformInstanceId).ps1 -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformId.ToLower())-template.ps1 $overwatchRoot\initialize\initialize-platform-$($platformId.ToLower()).ps1 -WhatIf
    $platformFiles += Copy-File $overwatchRoot\source\platform\$($platformId.ToLower())\initialize-platform-$($platformInstanceId)-template.ps1 $overwatchRoot\initialize\initialize-platform-$($platformInstanceId).ps1 -WhatIf

    $updatedFiles += $platformFiles

#endregion PLATFORM
#region PRODUCT

    $productFiles = @()
    foreach ($product in $global:Environ.Product) {
        $productFiles += Copy-File $overwatchRoot\source\product\$($product.ToLower())\install-product-$($product.ToLower()).ps1 $overwatchRoot\install\install-product-$($product.ToLower()).ps1 -WhatIf
        $productFiles += Copy-File $overwatchRoot\source\product\$($product.ToLower())\definitions-product-$($product.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-product-$($product.ToLower()).ps1 -WhatIf
        $productFiles += Copy-File $overwatchRoot\source\product\$($product.ToLower())\$($product.ToLower()).ps1 $overwatchRoot\$($product.ToLower()).ps1 -WhatIf
    }
    $updatedFiles += $productFiles

#endregion PRODUCT
#region PROVIDER                    

    $providerFiles = @()
    foreach ($provider in $global:Environ.Provider) {
        $providerFiles += Copy-File $overwatchRoot\source\providers\$($provider.ToLower())\install-provider-$($provider.ToLower()).ps1 $overwatchRoot\install\install-provider-$($provider.ToLower()).ps1 -WhatIf
        $providerFiles += Copy-File $overwatchRoot\source\providers\$($provider.ToLower())\definitions-provider-$($provider.ToLower())-template.ps1 $overwatchRoot\definitions\definitions-provider-$($provider.ToLower()).ps1 -WhatIf
        $providerFiles += Copy-File $overwatchRoot\source\providers\$($provider.ToLower())\provider-$($provider.ToLower()).ps1 $overwatchRoot\providers\provider-$($provider.ToLower()).ps1 -WhatIf
    }
    $updatedFiles += $providerFiles

#endregion PROVIDER

Write-Host+

# foreach ($updatedFile in $updatedfiles) {
#     Compare-Object -ReferenceObject (Get-Content $updatedFile.Source.FullName) -DifferenceObject (Get-Content $updatedFile.Destination)
# }
