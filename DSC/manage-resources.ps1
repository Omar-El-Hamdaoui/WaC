function Install-resources {
    param(
        [Parameter()]
        [string]$RepositoryName = "WaCLocalRepo"
    )

    Install-PSResource -Name MyResources -Repository $RepositoryName -TrustRepository 

    $installedModule = Get-Module -Name MyResources -ListAvailable | Select-Object -First 1

    if (-not $installedModule) {
        Write-Host "  ✗ Erreur : Module MyResources non trouvé après installation" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Module installé :" -ForegroundColor Gray
    Write-Host "    Version : $($installedModule.Version)" -ForegroundColor Gray
    Write-Host "    Chemin  : $($installedModule.ModuleBase)" -ForegroundColor Gray
}



function Update-Resources {
    param(
        [Parameter()]
        [string]$RepositoryName = "WaCLocalRepo"
    )

    Update-PSResource -Name MyResources -Repository $RepositoryName -TrustRepository

    $updatedModule = Get-InstalledPSResource -Name MyResources -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $updatedModule) {
        Write-Host "  ✗ Erreur : Module MyResources non trouvé après mise à jour" -ForegroundColor Red
        exit 1
    }

    Write-Host "  Module mis à jour :" -ForegroundColor Gray
    Write-Host "    Version : $($updatedModule.Version)" -ForegroundColor Gray
    Write-Host "    Chemin  : $($updatedModule.InstalledLocation)" -ForegroundColor Gray
}



function Remove-Resources {
    param(
        [Parameter()]
        [string]$RepositoryName = "WaCLocalRepo"
    )

    Uninstall-PSResource -Name MyResources -ErrorAction SilentlyContinue

    $installedModule = Get-InstalledPSResource -Name MyResources -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($installedModule) {
        Write-Host "  ✗ Erreur : Module MyResources est encore présent après suppression" -ForegroundColor Red
        exit 1
    }

    Write-Host "  ✓ Module MyResources supprimé avec succès" -ForegroundColor Green


}
