    #region DEFINITIONS
    
        # update powershell format data and type data for custom views
        # custom view files (.ps1xml) are located in $global:Location.Views
        foreach ($view in (Get-ChildItem -Path $global:Location.Views -Filter *.ps1xml)) {

            if (!(Get-FormatData -TypeName $view.FullName)) {
                Update-FormatData -AppendPath $view.FullName
            }
            else {
                Update-FormatData
            }

            $formatData = Get-FormatData -TypeName Overwatch.Log.Summary
            $formatDataHeaders = $formatData.FormatViewDefinition.Control.Headers
            $defaultDisplayProperty = "`"$($formatDataHeaders[0].Label)`""
            $defaultDisplayPropertySet = "`"$(($formatDataHeaders.Label | Where-Object {$_.Trim().Length -gt 0}) -join '", "')`""

            Remove-TypeData -TypeName $view.FullName -ErrorAction SilentlyContinue

            $typeData = @{
                DefaultDisplayProperty = $defaultDisplayProperty
                DefaultDisplayPropertySet = $defaultDisplayPropertySet
            }
            Update-TypeData -TypeName $view.FullName @typeData

        }

    #endregion DEFINITIONS