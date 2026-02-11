param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

# Configuration des préférences d'erreur
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Lecture de l'entrée JSON depuis stdin
$inputJson = [Console]::In.ReadToEnd()
$inputObject = if ($inputJson) { 
    try {
        $inputJson | ConvertFrom-Json 
    }
    catch {
        @{ name = 'Chocolatey'; ensure = 'Present' }
    }
} else { 
    @{ name = 'Chocolatey'; ensure = 'Present' } 
}

#region Helper Functions

function Test-ChocolateyInstalled {
    try {
        $chocoPath = "$env:ProgramData\chocolatey\choco.exe"
        return (Test-Path $chocoPath)
    }
    catch {
        return $false
    }
}

function Get-ChocolateyVersion {
    try {
        if (Test-ChocolateyInstalled) {
            $version = & "$env:ProgramData\chocolatey\choco.exe" --version 2>$null
            return $version.Trim()
        }
        return $null
    }
    catch {
        return $null
    }
}

#endregion

#region DSC Operations

function Get-ResourceState {
    param($InputObject)
    
    $logEntry = @{
        message = "Hello from Get-ResourceState "
        level   = "error"
    }
    
    $jsonLog = $logEntry | ConvertTo-Json -Compress
    [Console]::Error.WriteLine($jsonLog)

    try {
        $isInstalled = Test-ChocolateyInstalled
        
        $state = @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Chocolatey' }
            ensure = if ($isInstalled) { 'Present' } else { 'Absent' }
        }
        
        # Ajouter des infos supplémentaires si installé
        if ($isInstalled) {
            $version = Get-ChocolateyVersion
            if ($version) {
                $state.version = $version
            }
            $state.installPath = "$env:ProgramData\chocolatey"
        }
        
        return $state
    }
    catch {
        # En cas d'erreur, retourner un état minimal valide
        return @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Chocolatey' }
            ensure = 'Absent'
            error = $_.Exception.Message
        }
    }
}

function Test-ResourceState {
    param($InputObject)
    
    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
        
        $inDesiredState = ($currentState.ensure -eq $desiredEnsure)
        
        $currentState._inDesiredState = $inDesiredState
        return $currentState
    }
    catch {
        # Retourner un état avec erreur mais JSON valide
        return @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Chocolatey' }
            ensure = 'Absent'
            _inDesiredState = $false
            error = $_.Exception.Message
        }
    }
}

function Set-ResourceState {
    param($InputObject)
    
    $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
    
    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        
        # Ne faire des changements que si nécessaire
        if ($currentState.ensure -ne $desiredEnsure) {
            if ($desiredEnsure -eq 'Present') {
                # Installer Chocolatey
                if (-not (Test-ChocolateyInstalled)) {
                    try {
                        # Configuration de la sécurité
                        Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
                        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                        
                        # Télécharger et exécuter le script d'installation
                        $installScript = Invoke-RestMethod -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing -ErrorAction Stop
                        
                        # Exécuter dans un bloc try-catch séparé
                        try {
                            Invoke-Expression $installScript
                        }
                        catch {
                            # L'installation peut générer des warnings, mais réussir quand même
                            # Vérifier si Chocolatey est maintenant installé
                            if (-not (Test-ChocolateyInstalled)) {
                                throw "Installation failed: $_"
                            }
                        }
                        
                        # Rafraîchir PATH
                        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + 
                                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
                    }
                    catch {
                        # Retourner l'état avec l'erreur mais ne pas exit 1
                        $errorState = Get-ResourceState -InputObject $InputObject
                        $errorState.error = "Installation failed: $($_.Exception.Message)"
                        return $errorState
                    }
                }
            }
            elseif ($desiredEnsure -eq 'Absent') {
                # Désinstaller Chocolatey
                if (Test-ChocolateyInstalled) {
                    try {
                        $chocoPath = "$env:ProgramData\chocolatey"
                        
                        # Supprimer le répertoire Chocolatey
                        if (Test-Path $chocoPath) {
                            Remove-Item -Path $chocoPath -Recurse -Force -ErrorAction Stop
                        }
                        
                        # Nettoyer les variables d'environnement
                        $envVars = @('ChocolateyInstall', 'ChocolateyToolsLocation', 'ChocolateyLastPathUpdate')
                        $scopes = @([System.EnvironmentVariableTarget]::Machine, [System.EnvironmentVariableTarget]::User)
                        
                        foreach ($envVar in $envVars) {
                            foreach ($scope in $scopes) {
                                try {
                                    $value = [System.Environment]::GetEnvironmentVariable($envVar, $scope)
                                    if ($value) {
                                        [System.Environment]::SetEnvironmentVariable($envVar, $null, $scope)
                                    }
                                }
                                catch {
                                    # Continuer même si une variable ne peut pas être supprimée
                                }
                            }
                        }
                        
                        # Nettoyer PATH
                        foreach ($scope in $scopes) {
                            try {
                                $path = [System.Environment]::GetEnvironmentVariable('Path', $scope)
                                if ($path) {
                                    $newPath = ($path -split ';' | Where-Object { $_ -notlike '*chocolatey*' }) -join ';'
                                    [System.Environment]::SetEnvironmentVariable('Path', $newPath, $scope)
                                }
                            }
                            catch {
                                # Continuer même si PATH ne peut pas être modifié
                            }
                        }
                    }
                    catch {
                        # Retourner l'état avec l'erreur mais ne pas exit 1
                        $errorState = Get-ResourceState -InputObject $InputObject
                        $errorState.error = "Uninstallation failed: $($_.Exception.Message)"
                        return $errorState
                    }
                }
            }
        }
        
        # Retourner le nouvel état
        return Get-ResourceState -InputObject $InputObject
    }
    catch {
        # En cas d'erreur générale, retourner un état avec l'erreur
        $errorState = Get-ResourceState -InputObject $InputObject
        $errorState.error = $_.Exception.Message
        return $errorState
    }
}

#endregion

# Exécution de l'opération
try {
    $result = switch ($Operation) {
        'Get'  { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set'  { Set-ResourceState -InputObject $inputObject }
    }
    
    # Sortie en JSON (toujours réussir avec un JSON valide)
    $jsonOutput = $result | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput
    
    # Exit 0 même si des erreurs mineures sont présentes
    exit 0
}
catch {
    # Dernier filet de sécurité : retourner un JSON d'erreur mais exit 0
    $errorOutput = @{
        name = if ($inputObject.name) { $inputObject.name } else { 'Chocolatey' }
        ensure = 'Absent'
        error = $_.Exception.Message
        _inDesiredState = $false
    }
    
    $jsonOutput = $errorOutput | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput
    
    # Exit 0 pour que DSC puisse lire le JSON d'erreur
    exit 0
}