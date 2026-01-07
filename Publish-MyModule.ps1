[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Major', 'Minor', 'Patch')]
    [string]$VersionBump,
    
    [Parameter()]
    [string]$ReleaseNotes,
    
    [Parameter()]
    [string]$ModulePath,
    
    [Parameter()]
    [string]$RepositoryPath
)

# --- Détection des chemins ---
if (-not $ModulePath) {
    $ModulePath = Join-Path $PSScriptRoot "MyDscResources"
    Write-Host "ModulePath auto-détecté: $ModulePath" -ForegroundColor Gray
}

if (-not $RepositoryPath) {
    $RepositoryPath = Join-Path $PSScriptRoot "PSRepository"
    Write-Host "RepositoryPath auto-détecté: $RepositoryPath" -ForegroundColor Gray
}

Write-Host "Publication du module MyDscResources..." -ForegroundColor Cyan

$manifestPath = Join-Path $ModulePath "MyDscResources.psd1"

# ====================================
# GESTION DE LA VERSION (MÉTHODE ROBUSTE)
# ====================================
try {
    $manifest = Import-PowerShellDataFile $manifestPath
    $currentVersion = [version]$manifest.ModuleVersion
}
catch {
    Write-Host "✗ Erreur: Impossible de charger le manifeste du module à l'emplacement $manifestPath" -ForegroundColor Red
    exit 1
}

if ($VersionBump) {
    Write-Host "`nMise à jour de la version..." -ForegroundColor Yellow
    
    $newVersion = switch ($VersionBump) {
        'Major' { [version]::new($currentVersion.Major + 1, 0, 0) }
        'Minor' { [version]::new($currentVersion.Major, $currentVersion.Minor + 1, 0) }
        'Patch' { [version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1) }
    }
    
    Write-Host "  Bumping version: $currentVersion → $newVersion" -ForegroundColor Cyan
    
    # *** SAUVEGARDE DU MANIFESTE ORIGINAL ***
    $backupPath = "$manifestPath.backup"
    Copy-Item $manifestPath $backupPath -Force
    
    try {
        # *** MODIFICATION MANUELLE PLUS PRÉCISE ***
        $manifestContent = Get-Content $manifestPath -Raw -Encoding UTF8
        
        # Mise à jour de la version avec pattern plus strict
        $manifestContent = $manifestContent -replace "(ModuleVersion\s*=\s*)'[\d\.]+'", "`$1'$newVersion'"
        
        if ($ReleaseNotes) {
            # Échapper les apostrophes dans les release notes
            $escapedNotes = $ReleaseNotes -replace "'", "''"
            
            # Mise à jour ou ajout des ReleaseNotes
            if ($manifestContent -match "ReleaseNotes\s*=") {
                $manifestContent = $manifestContent -replace "(ReleaseNotes\s*=\s*)'[^']*'", "`$1'$escapedNotes'"
            } else {
                # Insérer après ModuleVersion
                $manifestContent = $manifestContent -replace "(ModuleVersion\s*=\s*'[\d\.]+')", "`$1`n    ReleaseNotes = '$escapedNotes'"
            }
        }
        
        # Écrire le nouveau contenu avec BOM UTF-8
        $utf8WithBom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($manifestPath, $manifestContent, $utf8WithBom)
        
        Write-Host "✓ Manifeste mis à jour" -ForegroundColor Green
        
        # *** VALIDATION DU MANIFESTE ***
        Write-Host "  Validation du manifeste..." -ForegroundColor Gray
        $testResult = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop -WarningAction SilentlyContinue
        
        if ($testResult.Version -eq $newVersion) {
            Write-Host "✓ Manifeste validé avec succès" -ForegroundColor Green
            Remove-Item $backupPath -Force
        } else {
            throw "La version du manifeste ne correspond pas"
        }
        
        $versionToPublish = $newVersion
    }
    catch {
        Write-Host "✗ Erreur lors de la mise à jour du manifeste: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Restauration de la sauvegarde..." -ForegroundColor Yellow
        Copy-Item $backupPath $manifestPath -Force
        Remove-Item $backupPath -Force
        exit 1
    }
} else {
    $versionToPublish = $currentVersion
    Write-Host "`nPublication de la version courante: $versionToPublish (avec écrasement forcé)" -ForegroundColor Cyan
}

# ====================================
# SUPPRIMER ÉVENTUELLE VERSION EXISTANTE
# ====================================
$existingPackage = Join-Path $RepositoryPath "MyDscResources.$versionToPublish.nupkg"

if (Test-Path $existingPackage) {
    Write-Host "⚠ Une version identique existe déjà. Suppression et écrasement..." -ForegroundColor Yellow
    Remove-Item $existingPackage -Force
    Write-Host "✓ Ancien package supprimé" -ForegroundColor Green
} else {
    Write-Host "✓ Aucun package existant à supprimer." -ForegroundColor Gray
}

# ====================================
# CRÉATION AUTO DU REPOSITORY
# ====================================
if (-not (Test-Path $RepositoryPath)) {
    Write-Host "Création du dossier repository: $RepositoryPath" -ForegroundColor Gray
    New-Item -ItemType Directory -Path $RepositoryPath -Force | Out-Null
}

$repo = Get-PSRepository -Name WaCLocalRepo -ErrorAction SilentlyContinue

if (-not $repo) {
    Write-Host "Enregistrement du repository WaCLocalRepo..." -ForegroundColor Yellow
    Register-PSRepository `
        -Name WaCLocalRepo `
        -SourceLocation $RepositoryPath `
        -PublishLocation $RepositoryPath `
        -InstallationPolicy Trusted
    Write-Host "✓ Repository enregistré" -ForegroundColor Green
} else {
    Write-Host "Repository WaCLocalRepo déjà existant" -ForegroundColor Gray
}

# ====================================
# PUBLICATION DU MODULE
# ====================================
$originalLang = $env:DOTNET_CLI_UI_LANGUAGE
$originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
$originalUICulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture

try {
    $env:DOTNET_CLI_UI_LANGUAGE = "en-US"
    [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::new("en-US")
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::new("en-US")
    
    Write-Host "  Culture forcée en anglais" -ForegroundColor Gray
    
    Set-Location $ModulePath

    Publish-Module -Path . -Repository WaCLocalRepo -Verbose -Force
    
    Write-Host "✓ Module publié avec succès via Publish-Module" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Échec de Publish-Module, fallback copie manuelle..." -ForegroundColor Yellow
    Write-Host "  Erreur : $($_.Exception.Message)" -ForegroundColor Gray
    
    Start-Sleep -Seconds 2
    
    $packageName = "MyDscResources.$versionToPublish.nupkg"
    $searchPaths = @(
        "$env:LOCALAPPDATA\Temp\*\MyDscResources\$packageName",
        "$env:TEMP\*\MyDscResources\$packageName"
    )
    
    $packages = @()
    foreach ($pattern in $searchPaths) {
        $found = Get-ChildItem -Path $pattern -Recurse -ErrorAction SilentlyContinue
        if ($found) {
            $packages += $found
        }
    }
    
    if ($packages.Count -eq 0) {
        Write-Host "  Package exact non trouvé, recherche large..." -ForegroundColor Gray
        $cutoffTime = (Get-Date).AddSeconds(-30)
        $packages = Get-ChildItem -Path "$env:LOCALAPPDATA\Temp" -Filter "MyDscResources.*.nupkg" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $cutoffTime }
    }
    
    if ($packages.Count -gt 0) {
        $latestPackage = $packages | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Write-Host "  Package trouvé : $($latestPackage.FullName)" -ForegroundColor Gray
        
        Copy-Item -Path $latestPackage.FullName -Destination $RepositoryPath -Force
        Write-Host "✓ Package copié manuellement vers le repository" -ForegroundColor Green
    } else {
        Write-Host "✗ Package non trouvé" -ForegroundColor Red
    }
}
finally {
    if ($originalLang) {
        $env:DOTNET_CLI_UI_LANGUAGE = $originalLang
    } else {
        Remove-Item Env:\DOTNET_CLI_UI_LANGUAGE -ErrorAction SilentlyContinue
    }
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $originalUICulture
}

# ====================================
# VÉRIFICATION FINALE
# ====================================
Write-Host "`nVérification du module dans le repository..." -ForegroundColor Cyan
$module = Find-Module -Repository WaCLocalRepo -Name MyDscResources -ErrorAction SilentlyContinue

if ($module) {
    Write-Host "✓ Module trouvé dans le repository" -ForegroundColor Green
    Write-Host "  Nom     : $($module.Name)" -ForegroundColor Gray
    Write-Host "  Version : $($module.Version)" -ForegroundColor Gray
} else {
    Write-Host "⚠ Module non trouvé via Find-Module" -ForegroundColor Yellow
    Write-Host "  Contenu du repository :" -ForegroundColor Cyan
    Get-ChildItem $RepositoryPath -Filter "*.nupkg" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "    ✓ $($_.Name)" -ForegroundColor Green }
}

Write-Host "`n=== Publication terminée ===" -ForegroundColor Green