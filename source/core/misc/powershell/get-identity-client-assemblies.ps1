[AppDomain]::CurrentDomain.GetAssemblies() | ?{ $_.GetName().Name -eq 'Microsoft.Identity.Client' } | Select-Object FullName,Location
