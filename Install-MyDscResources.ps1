#Requires -RunAsAdministrator
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



# ====================================
# ÉTAPE 0A : PRÉ-REQUIS
# ====================================
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
Set-PSRepository PSGallery -InstallationPolicy Trusted


$targetPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Modules"

if (-not (Test-Path $targetPath)) {
    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
}

Install-Module powershell-yaml
Install-Module PSDscResources -Repository PSGallery
Install-Module PSDesiredStateConfiguration -Repository PSGallery
Install-Module Microsoft.WinGet.DSC
Install-Module Microsoft.VisualStudio.DSC


# ====================================
# ÉTAPE 0B : PRÉ-REQUIS
# ====================================
    
Write-Host "`n0. Pré-requis (Auto-Install)..." -ForegroundColor Yellow

# 1. Vérif Winget (Obligatoire)
if (-not (Get-Command winget -EA SilentlyContinue)) { Write-Host " ✗ Winget manquant !" -F Red; exit 1 }

# 2. PowerShell 7 (Si absent, on installe en silence)
if (-not (Get-Command pwsh -EA SilentlyContinue)) { 
    Write-Host "   Installation PowerShell 7..." -ForegroundColor Cyan
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
    Write-Host "   ⚠ Relancez le script après l'installation !" -ForegroundColor Yellow
}

$pkgInfo = (winget search DesiredStateConfiguration --source msstore --exact --accept-source-agreements |
        Where-Object { $_ -match '^DesiredStateConfiguration\s' } |
        Select-Object -First 1).ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[1]


# 3. DSC v3 (Si absent, on installe en silence)
if (-not (Get-Command dsc -EA SilentlyContinue)) {
    Write-Host "   Installation DSC v3..." -ForegroundColor Cyan
    winget install --id $pkgInfo --source msstore --accept-package-agreements --accept-source-agreements --silent
}

Write-Host "   ✓ Pré-requis validés." -ForegroundColor Green

Write-Host "=== INSTALLATION DE MyDscResources ===" -ForegroundColor Cyan
# ====================================
# ÉTAPE 1 : ENREGISTREMENT DU REPOSITORY
# ====================================
Write-Host "`n1. Vérification du repository..." -ForegroundColor Yellow

# Utilisation du RepositoryPath dynamique
$existingRepo = Get-PSRepository -Name $RepositoryName -ErrorAction SilentlyContinue

if (-not $existingRepo) {
    Write-Host "  Repository '$RepositoryName' non trouvé, enregistrement..." -ForegroundColor Gray
    Register-PSResourceRepository -Name $RepositoryName -Uri $RepositoryPath -Trusted
    Write-Host "  ✓ Repository enregistré" -ForegroundColor Green
} else {
    Write-Host "  ✓ Repository déjà enregistré" -ForegroundColor Green
}

# ====================================
# Delete Old versions
# ====================================
Write-Host "   Vérification des anciennes versions..." -ForegroundColor Gray

$oldVersions = Get-Module -Name MyDscResources -ListAvailable

if ($oldVersions) {
    foreach ($ver in $oldVersions) {
        Write-Host "   Suppression de la version existante : $($ver.Version) située dans $($ver.ModuleBase)" -ForegroundColor Magenta

        Remove-Item -Path $ver.ModuleBase -Recurse -Force -ErrorAction Stop
        Write-Host "   ✓ Version $($ver.Version) supprimée." -ForegroundColor Green
    }
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


$dscResourcePath = Join-Path $installedModule.ModuleBase "resources"


Write-Host " Dossier des ressources identifié : $dscResourcePath" -ForegroundColor Gray

$resourceDirs = Get-ChildItem $dscResourcePath -Directory

# ====================================
# ÉTAPE 4 : CONFIGURATION PATH
# ====================================
Write-Host "`n4. Configuration de PATH..." -ForegroundColor Yellow

# 1. On construit une seule liste avec TOUS les chemins nécessaires
$pathList = @(
    $resourceDirs.FullName                                  # Tes ressources
    $PSHOME                                                 # PowerShell 7 
    [Environment]::SystemDirectory                          # System32 
    (Get-Module Microsoft.WinGet.DSC -ListAvailable).ModuleBase # WinGet
    $env:Path.Split([IO.Path]::PathSeparator)                     # Les chemins déjà présents dans PATH 
) | Where-Object { $_ } | Select-Object -Unique

# 2. On joint tout avec le séparateur (;)
$finalPath = $pathList -join [IO.Path]::PathSeparator

# 3. On applique la configuration (Persistant + Session)
[Environment]::SetEnvironmentVariable("PATH", $finalPath, "User")
$env:PATH = $finalPath

Write-Host " ✓ Variable PATH mise à jour." -ForegroundColor Green
Write-Host "   Chemin : $finalPath" -ForegroundColor DarkGray


# ====================================
# ÉTAPE 5 : VÉRIFICATION
# ====================================
Write-Host "`n5. Vérification..." -ForegroundColor Yellow
Write-Host "DSC resources :" -ForegroundColor Gray
dsc resource list

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