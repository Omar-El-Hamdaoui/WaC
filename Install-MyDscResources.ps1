[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryPath = (Join-Path $PSScriptRoot "PSRepository"),
    
    [Parameter()]
    [string]$RepositoryName = "WaCLocalRepo",
    
    [Parameter()]
    [switch]$Force
)

Write-Host "=== INSTALLATION DE MyDscResources ===" -ForegroundColor Cyan

# # ====================================
# # ÉTAPE 0A : VÉRIFICATION ET INSTALLATION DE SCOOP
# # ====================================
# Write-Host "`n0a. Vérification de Scoop..." -ForegroundColor Yellow

# function Test-ScoopInstalled {
#     try {
#         $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue
#         return $null -ne $scoopCommand
#     }
#     catch {
#         return $false
#     }
# }

# function Install-ScoopIfMissing {
#     if (Test-ScoopInstalled) {
#         Write-Host "  ✓ Scoop est déjà installé" -ForegroundColor Green
#         try {
#             $version = & scoop --version 2>$null
#             Write-Host "    Version: $version" -ForegroundColor Gray
#         }
#         catch {
#             Write-Host "    (version non disponible)" -ForegroundColor Gray
#         }
#         return $true
#     }
    
#     Write-Host "  ⚠ Scoop n'est pas installé, installation en cours..." -ForegroundColor Yellow
    
#     try {
#         # ⭐ FORCER TLS 1.2 POUR LA CONNEXION SSL ⭐
#         [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
#         # Configuration de la politique d'exécution
#         Write-Host "    Configuration de la politique d'exécution..." -ForegroundColor Gray
#         Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        
#         # Télécharger et exécuter le script d'installation
#         Write-Host "    Téléchargement du script d'installation Scoop..." -ForegroundColor Gray
#         $installScript = Invoke-RestMethod -Uri 'https://get.scoop.sh' -UseBasicParsing -ErrorAction Stop
        
#         Write-Host "    Exécution de l'installation..." -ForegroundColor Gray
#         Invoke-Expression $installScript 
        
#     }
#     catch {
#     }
# }

# # Exécuter la vérification/installation de Scoop
# Install-ScoopIfMissing

# ====================================
# ÉTAPE 0B : CONFIGURATION DU PSMODULEPATH UTILISATEUR
# But : S'assurer que les modules installés par l'utilisateur sont trouvés.
# ====================================
Write-Host "`n0b. Vérification et configuration du PSModulePath..." -ForegroundColor Yellow

$userModulePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Modules"
$currentPSModulePath = $env:PSModulePath -split [IO.Path]::PathSeparator

if (-not ($currentPSModulePath -contains $userModulePath)) {
    Write-Host "  Chemin utilisateur manquant. Ajout de '$userModulePath'..." -ForegroundColor Gray
    
    # 1. Mise à jour persistante (Variable Utilisateur)
    $existingUserPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
    if ($existingUserPath -notlike "*$userModulePath*") {
        # Ajoute le nouveau chemin en premier pour qu'il soit prioritaire
        $newPath = "$userModulePath" + [IO.Path]::PathSeparator + $existingUserPath
        [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")
        Write-Host "  ✓ PSModulePath utilisateur persistante mis à jour." -ForegroundColor Green
    }

    # 2. Mise à jour pour la session actuelle (immédiat)
    $env:PSModulePath = "$userModulePath" + [IO.Path]::PathSeparator + $env:PSModulePath
    Write-Host "  ✓ PSModulePath de session mis à jour." -ForegroundColor Green
} else {
    Write-Host "  ✓ PSModulePath utilisateur déjà présent." -ForegroundColor Green
}


# ====================================
# ÉTAPE 1 : ENREGISTREMENT DU REPOSITORY
# ====================================
Write-Host "`n1. Vérification du repository..." -ForegroundColor Yellow

# Utilisation du RepositoryPath dynamique
$existingRepo = Get-PSRepository -Name $RepositoryName -ErrorAction SilentlyContinue

if (-not $existingRepo) {
    Write-Host "  Repository '$RepositoryName' non trouvé, enregistrement..." -ForegroundColor Gray
    Register-PSRepository -Name $RepositoryName -SourceLocation $RepositoryPath -InstallationPolicy Trusted
    Write-Host "  ✓ Repository enregistré" -ForegroundColor Green
} else {
    Write-Host "  ✓ Repository déjà enregistré" -ForegroundColor Green
}

# ====================================
# ÉTAPE 2 : INSTALLATION DU MODULE MyDscResources
# ====================================
Write-Host "`n2. Installation du module MyDscResources..." -ForegroundColor Yellow

try {
    if ($Force) {
        Write-Host "  Mode forcé : réinstallation complète..." -ForegroundColor Gray
        Install-PSResource -Name MyDscResources -Repository $RepositoryName -Reinstall -TrustRepository -ErrorAction Stop
    } else {
        Install-PSResource -Name MyDscResources -Repository $RepositoryName -TrustRepository -ErrorAction Stop
    }
    Write-Host "  ✓ Module installé avec Install-PSResource" -ForegroundColor Green
}
catch {
    Write-Host "  Install-PSResource a échoué, tentative avec Install-Module..." -ForegroundColor Yellow
    if ($Force) {
        Install-Module -Name MyDscResources -Repository $RepositoryName -Force -Scope CurrentUser
    } else {
        Install-Module -Name MyDscResources -Repository $RepositoryName -Scope CurrentUser
    }
    Write-Host "  ✓ Module installé avec Install-Module" -ForegroundColor Green
}

# Vérifier l'installation de MyDscResources
$installedModule = Get-Module -Name MyDscResources -ListAvailable | Select-Object -First 1
if (-not $installedModule) {
    Write-Host "  ✗ Erreur : Module MyDscResources non trouvé après installation" -ForegroundColor Red
    exit 1
}
Write-Host "  Module installé :" -ForegroundColor Gray
Write-Host "    Version : $($installedModule.Version)" -ForegroundColor Gray
Write-Host "    Chemin  : $($installedModule.ModuleBase)" -ForegroundColor Gray


# ====================================
# ÉTAPE 3 : CONFIGURATION DSC
# ====================================
Write-Host "`n3. Configuration de DSC..." -ForegroundColor Yellow

$modulePath = $installedModule.ModuleBase

# Détecter le bon dossier (resources ou dsc_resources)
$resourceFolder = $null
foreach ($folder in @("resources", "dsc_resources")) {
    $testPath = Join-Path $modulePath $folder
    if (Test-Path $testPath) {
        $resourceFolder = $folder
        break
    }
}

if (-not $resourceFolder) {
    Write-Host "  ✗ Aucun dossier de ressources trouvé (resources ou dsc_resources)" -ForegroundColor Red
    exit 1
}

$dscResourcePath = Join-Path $modulePath $resourceFolder
Write-Host "  Dossier des ressources : $dscResourcePath" -ForegroundColor Gray

# Lister les ressources disponibles
$resourceDirs = Get-ChildItem $dscResourcePath -Directory
Write-Host "  Ressources disponibles :" -ForegroundColor Gray
$resourceDirs | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Cyan }

# ====================================
# ÉTAPE 4 : CONFIGURATION DSC_RESOURCE_PATH
# ====================================
Write-Host "`n4. Configuration de DSC_RESOURCE_PATH..." -ForegroundColor Yellow

# IMPORTANT : Construire le chemin pour chaque ressource individuellement
$resourcePaths = $resourceDirs | ForEach-Object { $_.FullName }

# Ajouter les chemins système et autres dépendances
$pwshPath = "C:\Program Files\PowerShell\7"
$userModulesPath = "C:\Windows\System32"
$allPaths = $resourcePaths + $pwshPath + $userModulesPath


####
try {
    # Tenter de localiser le répertoire WinGet DSC (utilisé pour les dépendances)
    $winGetModulePath = (Get-Module -ListAvailable -Name Microsoft.WinGet.DSC).Path
    
    if ($winGetModulePath) {
        $winGetDir = Split-Path $winGetModulePath -Parent
        $allPaths = $allPaths + $winGetDir
        Write-Host "  Chemin spécifique WinGet DSC ajouté: $winGetDir" -ForegroundColor Gray
    } else {
        Write-Warning "  Le module Microsoft.WinGet.DSC n'a pas pu être localisé."
    }
}
catch {
    Write-Warning "  Erreur lors de la détermination du chemin de Microsoft.WinGet.DSC : $($_.Exception.Message)"
}
####

$newDscResourcePath = $allPaths -join [IO.Path]::PathSeparator

Write-Host "  Configuration du chemin avec $($resourceDirs.Count + 2) ressource(s)..." -ForegroundColor Gray

# Mettre à jour la variable utilisateur (persistante)
[Environment]::SetEnvironmentVariable("DSC_RESOURCE_PATH", $newDscResourcePath, "User")
Write-Host "  ✓ Variable utilisateur mise à jour" -ForegroundColor Green

# Mettre à jour la session actuelle (immédiat)
$env:DSC_RESOURCE_PATH = $newDscResourcePath
Write-Host "  ✓ Variable de session mise à jour" -ForegroundColor Green

# Afficher la configuration
Write-Host "`n  Chemins configurés :" -ForegroundColor Gray
$env:DSC_RESOURCE_PATH -split [IO.Path]::PathSeparator | ForEach-Object {
    $resourceName = Split-Path $_ -Leaf
    Write-Host "    📦 $resourceName" -ForegroundColor Cyan
}


# ====================================
# ÉTAPE 5 : VÉRIFICATION
# ====================================
Write-Host "`n5. Vérification..." -ForegroundColor Yellow

# AJOUT DE L'ANCIEN MODULE POUR LA COMPATIBILITÉ 'DSC'
Import-Module PSDesiredStateConfiguration -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1 # Laisser le temps à l'environnement de se mettre à jour

try {
    # 1. Tenter de trouver la commande 'dsc'
    $dscCommand = Get-Command dsc -ErrorAction Stop
    Write-Host "  ✓ Commande 'dsc' trouvée : $($dscCommand.Path)" -ForegroundColor Green
}
catch {
    # Échec critique si ni le binaire dsc, ni Get-DscResource ne fonctionnent
    Write-Host "  ✗ Erreur critique : La commande 'dsc' ou 'Get-DscResource' n'est pas fonctionnelle." -ForegroundColor Red
    Write-Host "    Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  ⚠ Cause la plus probable : Le binaire 'dsc.exe' ou le moteur DSC est indisponible. Un redémarrage de la session/VM est fortement recommandé." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n=== INSTALLATION TERMINÉE ===" -ForegroundColor Green
Write-Host "`nRésumé:" -ForegroundColor Cyan
Write-Host "  ✓ MyDscResources: v$($installedModule.Version)" -ForegroundColor Gray
Write-Host "  ✓ Ressources DSC: $($resourceDirs.Count) disponible(s)" -ForegroundColor Gray