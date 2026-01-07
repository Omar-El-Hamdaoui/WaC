[CmdletBinding()]
param()

Write-Host "=== AJOUT DE PWSH AU PATH ===" -ForegroundColor Cyan

# Trouver pwsh.exe
$pwshPaths = @(
    "C:\Program Files\PowerShell\7\pwsh.exe",
    "C:\Program Files\PowerShell\7-preview\pwsh.exe",
    "${env:ProgramFiles}\PowerShell\7\pwsh.exe",
    "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
)

$pwshExe = $null
foreach ($path in $pwshPaths) {
    if (Test-Path $path) {
        $pwshExe = $path
        break
    }
}

if (-not $pwshExe) {
    Write-Host "✗ pwsh.exe non trouvé !" -ForegroundColor Red
    Write-Host "  Installez PowerShell 7+ depuis : https://aka.ms/powershell" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ pwsh.exe trouvé : $pwshExe" -ForegroundColor Green

# Obtenir le répertoire parent
$pwshDir = Split-Path $pwshExe -Parent
Write-Host "  Répertoire : $pwshDir" -ForegroundColor Gray

# Vérifier si déjà dans le PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -like "*$pwshDir*") {
    Write-Host "✓ Le répertoire est déjà dans le PATH utilisateur" -ForegroundColor Green
} else {
    Write-Host "  Ajout au PATH utilisateur..." -ForegroundColor Yellow
    $newPath = "$currentPath;$pwshDir"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "✓ PATH utilisateur mis à jour" -ForegroundColor Green
}

# Mettre à jour la session actuelle
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
            [Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "`n=== VÉRIFICATION ===" -ForegroundColor Cyan
try {
    $version = & pwsh --version
    Write-Host "✓ pwsh est maintenant accessible : $version" -ForegroundColor Green
} catch {
    Write-Host "⚠ pwsh ajouté au PATH mais nécessite un redémarrage de PowerShell" -ForegroundColor Yellow
}

Write-Host "`n=== TERMINÉ ===" -ForegroundColor Green
Write-Host "IMPORTANT : Redémarrez votre terminal PowerShell pour que les changements prennent effet" -ForegroundColor Yellow