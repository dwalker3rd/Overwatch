#region INITIALIZATION

    Initialize-AzureConfig
    $azureProfile = Connect-AzAccount+ -Tenant "<tenant>"
    if (!$azureProfile) {
        $message = "    Invalid Tenant ID, Subscription ID or Azure Admin Credentials."
        Write-Log -Target "Azure" -Action "Connect-AzAccount+" -Status "Error" -Message $message -EntryType "Error" -Force
        Write-Host+ -NoTrace -NoTimestamp $message -ForegroundColor Red
    }

#endregion INITIALIZATION