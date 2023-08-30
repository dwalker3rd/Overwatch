function global:Initialize-PlatformTopology {

    [CmdletBinding()]
    param (
        [switch]$ResetCache
    )
    
    if (!$ResetCache) {
        if ($(Get-Cache platformtopology).Exists) {
            return Read-Cache platformtopology
        }
    }

    $thisNode = $env:COMPUTERNAME.ToLower()
    
    $platformTopology = @{
        Nodes = @{
            $thisNode = @{
                ReadOnly = $true
            }
        }
        Alias = @{
            $thisNode = $thisNode
        }
    }
    
    $platformTopology | Write-Cache platformtopology
    
    return $platformTopology
    
    }
    Set-Alias -Name ptInit -Value Initialize-PlatformTopology -Scope Global

    function global:Show-PlatformStatus {

        [CmdletBinding(DefaultParameterSetName = "All")]
        param(
            [Parameter(Mandatory=$false,ParameterSetName="Summary")][switch]$Summary,
            [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$All,
            [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Required,
            [Parameter(Mandatory=$false,ParameterSetName="All")][switch]$Issues
        )
    
        if (!$Summary -and !$All) { $All = $true }

    }
    Set-Alias -Name platformStatus -Value Show-PlatformStatus -Scope Global