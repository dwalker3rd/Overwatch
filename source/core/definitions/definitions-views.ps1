foreach ($view in (Get-ChildItem -Path $global:Location.Views -Filter *.ps1xml)) {
    Update-FormatData -AppendPath $view
}