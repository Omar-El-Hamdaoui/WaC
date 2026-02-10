https://stackoverflow.com/questions/68992255/why-cant-export-variable-members-in-a-powershell-module-using-variablestoexport

https://powershellexplained.com/2016-11-06-powershell-hashtable-everything-you-wanted-to-know-about/#using-the-brackets-for-access
https://powershellexplained.com/2016-10-28-powershell-everything-you-wanted-to-know-about-pscustomobject/

https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-7.4

https://www.red-gate.com/simple-talk/sysadmin/powershell/powershell-time-saver-automatic-defaults/

https://medium.com/@justinricedev/creating-a-nuget-build-pipeline-for-powershell-modules-within-vsts-cb75e06161e0

// Check for PS modules updates

```powershell
Get-InstalledModule | ForEach-Object {
    $installedModule = $_
    # Determine if the installed module is a prerelease
    $isPrerelease = $installedModule.Version -match '-'
    $findModuleParams = @{
        Name = $installedModule.Name
    }
    if ($isPrerelease) {
        $findModuleParams['AllowPrerelease'] = $true
    }

    $latestModule = Find-Module @findModuleParams

    # Use version comparison that accounts for prerelease
    $installedVersion = $installedModule.Version
    $latestVersion = $latestModule.Version

    # Only proceed if there's a version difference, considering prerelease status
    if ($isPrerelease -or ($installedVersion -ne $latestVersion)) {
        # Further check to ensure we're only reporting genuine updates
        if (-not $isPrerelease -or ($isPrerelease -and $installedVersion -ne $latestVersion)) {
            [PSCustomObject]@{
                ModuleName = $installedModule.Name
                InstalledVersion = $installedModule.Version
                LatestVersion = $latestModule.Version
            }
        }
    }
} | Where-Object { $_ } | Format-Table -AutoSize
```

// Update PS module

```powershell
Update-Module -Name ModuleName
```

// List PS modules

```powershell
$env:PSModulePath -split ';' | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "=================================================="
        Write-Host "Modules in path: $_"
        Write-Host "=================================================="
        Get-ChildItem -Path $_ -Directory | ForEach-Object { " - $($_.Name)" }
    }
}
```

// Use WAC
Get-DscConfigurationState -YamlFilePath C:\Projets\WaC\DSCv2\ressources.yaml
Test-DscConfigurationState -YamlFilePath C:\Projets\WaC\DSCv2\ressources.yaml
Compare-DscConfigurationState -YamlFilePath C:\Projets\WaC\DSCv2\ressources.yaml -Report -JsonDiff
Set-DscConfigurationState -YamlFilePath C:\Projets\WaC\DSCv2\ressources.yaml -Report

// Prérequis ???
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
Set-PSRepository PSGallery -InstallationPolicy Trusted
Install-Module powershell-yaml
Install-Module PSDscResources -Repository PSGallery
Install-Module PSDesiredStateConfiguration -Repository PSGallery
Install-Module Microsoft.WinGet.DSC -AllowPrereleaseC:\Users\oelhamdaoui\OneDrive - Sopra Steria\Documents\PowerShell\Modules
Install-Module Microsoft.VisualStudio.DSC

Déposer les modules dans [Environment]::GetFolderPath("MyDocuments") -> \PowerShell\Modules
winget install -e -h --accept-package-agreements --accept-source-agreements --id Microsoft.PowerShell
