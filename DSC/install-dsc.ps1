<#
.SYNOPSIS
    Installe ou met à jour Microsoft Desired State Configuration v3.x.

.DESCRIPTION
    Utilise winget (Microsoft Store) pour déployer PowerShell 7.5 et DSC.
    Nécessite un shell en tant qu'administrateur.
    Lance automatiquement PowerShell 7 en administrateur à la fin.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryPath,    

    [Parameter()]
    [string]$RepositoryName = "WaCLocalRepo"
)

if (-not $RepositoryPath) {
    $RepositoryPath = Join-Path $PSScriptRoot "resources\PSRepository"
}

function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "le script doit être relancé dans PowerShell (v7) pour continuer." -ForegroundColor Red
        exit 1
    }

    Write-Host "PowerShell version $($PSVersionTable.PSVersion) détecté." -ForegroundColor Green

}


function InstallWinget {

    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue

    if (-not $wingetAvailable) {
        Write-Host "Winget non détecté. Tentative d'installation automatique..." -ForegroundColor Yellow
        
        $progressPreference = 'silentlyContinue'
        Write-Host "Installing WinGet PowerShell module from PSGallery..."
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
        Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
        Repair-WinGetPackageManager -AllUsers
        Write-Host "Done."
            
        $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue

    }

    if ($wingetAvailable) {
        Write-Host 'Winget disponible' -ForegroundColor Green
    }
    else {
        Write-Host 'Winget/App Installer est introuvable.' -ForegroundColor Red
        Write-Error "Veuillez installer 'App Installer' manuellement via le Microsoft Store."
        exit 1
    }
}


function InstallationPowerShell7 {

    $ps7Installed = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($ps7Installed) {
        $currentVersion = (pwsh --version).Split()[-1]
        Write-Host "  ℹ PowerShell 7 déjà installé (version $currentVersion)" -ForegroundColor Yellow
    }
    else {
        Write-Host '  → PowerShell 7 non détecté. Installation en cours...' -ForegroundColor White
        winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
    }


    if ($LASTEXITCODE -ne 0) {
        $acceptableExitCodes = @(
            0           # Success
            -1978335189 # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
        )
        if ($LASTEXITCODE -notin $acceptableExitCodes) {
            Write-Host "  ✗ Erreur lors de l'installation de PowerShell 7 (code $LASTEXITCODE)" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        else {
            Write-Host '  ✓ PowerShell 7 est déjà à jour' -ForegroundColor Green
        }
    }
    else {
        Write-Host '  ✓ PowerShell 7.5 installé avec succès' -ForegroundColor Green
    }

    # Vérification de l'installation
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Host "  ⚠ pwsh.exe n'est pas encore dans le PATH" -ForegroundColor Yellow
    }
    else {
        $installedVersion = (pwsh --version).Split()[-1]
        Write-Host "  ✓ PowerShell version $installedVersion disponible" -ForegroundColor Green
    }
}

function PréRequis {

    Test-PowerShellVersion

    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
    Set-PSResourceRepository -Name "PSGallery" -Trusted
}

function InstallationDesModules {

    Test-PowerShellVersion

    if ( -not (Get-Module -ListAvailable -Name Microsoft.WinGet.DSC )) {
        Install-PSResource -Name Microsoft.WinGet.DSC -Repository PSGallery -TrustRepository
    }

    if ( -not (Get-Module -ListAvailable -Name powershell-yaml )) {
        Install-PSResource -Name powershell-yaml -Repository PSGallery -TrustRepository
    }

    if ( -not (Get-Module -ListAvailable -Name Microsoft.VisualStudio.DSC )) {
        Install-PSResource -Name Microsoft.VisualStudio.DSC -Repository PSGallery -TrustRepository
    }

    if ( -not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client )) {
        Install-PSResource -Name Microsoft.WinGet.Client -Repository PSGallery -TrustRepository
    }
}


function InstallationDSC {

    if (-not (Get-Command dsc -ErrorAction SilentlyContinue)) {

        $pkgInfo = Find-WinGetPackage -Name "DesiredStateConfiguration" 
        winget install --id $pkgInfo.Id --source msstore --accept-package-agreements --accept-source-agreements --silent

        if ($LASTEXITCODE -ne 0) {
            $acceptableExitCodes = @(
                0           # Success
                -1978335189 # APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE
            )

            if ($LASTEXITCODE -notin $acceptableExitCodes) {
                Write-Host "  ✗ Erreur inattendue lors de l'installation de DSC ($LASTEXITCODE)" -ForegroundColor Red
                exit $LASTEXITCODE
            }
            else {
                Write-Host "  ✓ DSC est déjà installé ou à jour ($LASTEXITCODE)" -ForegroundColor Green
            }
        }
        else {
            Write-Host '  ✓ DSC installé avec succès' -ForegroundColor Green
        }
    }
    # Validation de l'installation
    if (-not (Get-Command dsc -ErrorAction SilentlyContinue)) {
        Write-Host "  ⚠ dsc.exe n'est pas dans le PATH actuel" -ForegroundColor Yellow
    }
    else {
        $dscVersion = (dsc --version).Split()[-1]
        Write-Host "  ✓ DSC v$dscVersion est installé" -ForegroundColor Green
    }

}


function EnregistrementRepository {

    Test-PowerShellVersion

    $existingRepo = Get-PSResourceRepository -Name $RepositoryName -ErrorAction SilentlyContinue

    if (-not $existingRepo) {
        Write-Host "  Repository '$RepositoryName' non trouvé, enregistrement..." -ForegroundColor Gray
        Register-PSResourceRepository -Name $RepositoryName -Uri $RepositoryPath -Trusted
        Write-Host "  ✓ Repository enregistré" -ForegroundColor Green
    } 
    else {
        Write-Host "  ✓ Repository déjà enregistré" -ForegroundColor Green
    }
}

# function SuppressionAnciennesRessources {
#     Write-Host "   Vérification des anciennes versions..." -ForegroundColor Gray

#     $oldVersions = Get-Module -Name MyResources -ListAvailable

#     if ($oldVersions) {
#         foreach ($ver in $oldVersions) {
#             Write-Host "   Suppression de la version existante : $($ver.Version) située dans $($ver.ModuleBase)" -ForegroundColor Magenta

#             Remove-Item -Path $ver.ModuleBase -Recurse -Force -ErrorAction Stop
#             Write-Host "   ✓ Version $($ver.Version) supprimée." -ForegroundColor Green
#         }
#     }
#     else {
#         Write-Host "   ✓ Aucune version précédente de MyResources détectée" -ForegroundColor Green
#     }

# }


function ConfigurationPath {

    $installedModule = Get-Module -Name MyResources -ListAvailable | Select-Object -First 1

    $DicoverResourceExtensionPath = $installedModule.ModuleBase

    $pathList = @(
        $DicoverResourceExtensionPath                                 # Le chemin de l'extension de découverte des ressources 
        $env:Path.Split([IO.Path]::PathSeparator)                     # Les chemins déjà présents dans PATH 
    ) | Where-Object { $_ } | Select-Object -Unique

    # On joint tout avec le séparateur (;)
    $finalPath = $pathList -join [IO.Path]::PathSeparator

    # On applique la configuration 
    [Environment]::SetEnvironmentVariable("PATH", $finalPath, "User")
    $env:PATH = $finalPath

    Write-Host " ✓ Variable PATH mise à jour." -ForegroundColor Green

}

. "$PSScriptRoot\manage-resources.ps1"

$functions = @(
    @{
        Message  = "Installation WinGet (si nécessaire)"
        Function = "InstallWinget"
    }
    @{
        Message  = "Installation de PowerShell 7.5"
        Function = "InstallationPowerShell7"    
    },
    @{
        Message  = "Configuration des pré-requis pour l'installation de DSC"
        Function = "PréRequis"    
    },
    @{
        Message  = "Installation des modules requis pour DSC"
        Function = "InstallationDesModules"
    },
    @{
        Message  = "Installation de DSC v3.x"
        Function = "InstallationDSC"
    },
    @{
        Message  = "Enregistrement du repository local"
        Function = "EnregistrementRepository"
    },
    # @{
    #     Message  = "Suppression des anciennes versions de ressources"
    #     Function = "SuppressionAnciennesRessources"
    # },
    @{
        Message  = "Installation des ressources DSC "
        Function = "Install-Resources"
    },
    @{
        Message  = "Configuration du PATH pour les ressources DSC"
        Function = "ConfigurationPath"
    }
)

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host '║        Installation DSC v3 & PowerShell 7.5                ║' -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan


$functionCount = $functions.count

for ($i = 0; $i -lt $functionCount; $i++) {

    $f = $functions[$i]

    $LargeurCadre = 75 

    $TexteEtape = "  Étape $($i + 1)/$functionCount : $($f.Message)"

    $LigneInterne = $TexteEtape.PadRight($LargeurCadre - 2)

    $BarreHorizontale = "─" * ($LargeurCadre - 2)

    Write-Host "`n┌$BarreHorizontale┐" -ForegroundColor Cyan
    Write-Host "│$LigneInterne│" -ForegroundColor Cyan
    Write-Host "└$BarreHorizontale┘" -ForegroundColor Cyan


    & $f.Function
}