function global:Use-View {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true,Position=0)][object]$View,
        [Parameter(ValueFromPipeline)][Object]$InputObject
    )
    begin{
        $outputObject = @()
    }
    process{
        $outputObject += $InputObject
    }
    end{
        $outputObject  | Select-Object -Property $View
    }
}