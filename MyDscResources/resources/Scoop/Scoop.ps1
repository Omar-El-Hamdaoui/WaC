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
        @{ name = 'Scoop'; ensure = 'Present' }
    }
} else { 
    @{ name = 'Scoop'; ensure = 'Present' } 
}

#region Helper Functions

function Test-ScoopInstalled {
    $scoopPath = Get-ScoopPath  
    if (-not $scoopPath) {      
        return $false            
    }

    $scoopExe = Join-Path $scoopPath "shims\scoop.ps1"
    return (Test-Path $scoopExe)
}

function Get-ScoopVersion {
    try {
        if (Test-ScoopInstalled) {
            $version = & scoop --version 2>$null
            if ($version -match 'v?(\d+\.\d+\.\d+)') {
                return $Matches[1]
            }
            return $version.Trim()
        }
        return $null
    }
    catch {
        return $null
    }
}

function Get-ScoopPath {
    try {
        # Scoop peut être installé dans plusieurs emplacements
        if ($env:SCOOP) {
            return $env:SCOOP
        }
        
        $defaultPath = Join-Path $env:USERPROFILE 'scoop'
        if (Test-Path $defaultPath) {
            return $defaultPath
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
    
    try {
        $isInstalled = Test-ScoopInstalled
        
        $state = @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
            ensure = if ($isInstalled) { 'Present' } else { 'Absent' }
        }
        
        # Ajouter des infos supplémentaires si installé
        if ($isInstalled) {
            $version = Get-ScoopVersion
            if ($version) {
                $state.version = $version
            }
            
            $installPath = Get-ScoopPath
            if ($installPath) {
                $state.installPath = $installPath
            }
        }
        
        return $state
    }
    catch {
        # En cas d'erreur, retourner un état minimal valide
        return @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
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
            name = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
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
                # Installer Scoop
                if (-not (Test-ScoopInstalled)) {
                    try {
                        # Configuration de la sécurité (comme Chocolatey)
                        Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
                        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                        
                        # Note: Ajout de https:// explicite ci-dessous pour éviter les erreurs
                        $installScript = Invoke-RestMethod -Uri 'https://get.scoop.sh' -UseBasicParsing -ErrorAction Stop
                        
                        # Exécuter dans un bloc try-catch séparé
                        try {
                            Invoke-Expression "& {$installScript} -RunAsAdmin"
                        }
                        catch {
                            # Vérifier si Scoop est maintenant installé malgré les erreurs (warnings)
                            if (-not (Test-ScoopInstalled)) {
                                throw "Installation failed: $_"
                            }
                        }
                        
                        # Rafraîchir PATH et environnement
                        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + 
                                    [System.Environment]::GetEnvironmentVariable('Path', 'User')
                    }
                    catch {
                        $errorState = Get-ResourceState -InputObject $InputObject
                        $errorState.error = "Installation failed: $($_.Exception.Message)"
                        return $errorState
                    }
                }
            }
            elseif ($desiredEnsure -eq 'Absent') {
                # Désinstaller Scoop
                if (Test-ScoopInstalled) {
                    try {
                        $scoopPath = Get-ScoopPath
                        if ($scoopPath -and (Test-Path $scoopPath)) {
                            Remove-Item -Path $scoopPath -Recurse -Force -ErrorAction Stop
                        }
                        
                        # Nettoyer les variables d'environnement Scoop
                        $envVars = @('SCOOP', 'SCOOP_GLOBAL')
                        $scopes = @([System.EnvironmentVariableTarget]::Machine, [System.EnvironmentVariableTarget]::User)
                        
                        foreach ($envVar in $envVars) {
                            foreach ($scope in $scopes) {
                                try {
                                    $value = [System.Environment]::GetEnvironmentVariable($envVar, $scope)
                                    if ($value) {
                                        [System.Environment]::SetEnvironmentVariable($envVar, $null, $scope)
                                    }
                                }
                                catch {}
                            }
                        }
                        
                        # Nettoyer PATH
                        foreach ($scope in $scopes) {
                            try {
                                $path = [System.Environment]::GetEnvironmentVariable('Path', $scope)
                                if ($path) {
                                    $newPath = ($path -split ';' | Where-Object { $_ -notlike '*scoop*' }) -join ';'
                                    [System.Environment]::SetEnvironmentVariable('Path', $newPath, $scope)
                                }
                            }
                            catch {}
                        }
                    }
                    catch {
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
        # Changement temporaire il faut  décommenter cette ligne plus tard
        #'Test' { Test-ResourceState -InputObject $inputObject } 
        'Test' { Test-ScoopInstalled -InputObject $inputObject }
        'Set'  { Set-ResourceState -InputObject $inputObject }
    }
    
    $jsonOutput = $result | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput
    
    exit 0
}
catch {
    $errorOutput = @{
        name = if ($inputObject.name) { $inputObject.name } else { 'Scoop' }
        ensure = 'Absent'
        error = $_.Exception.Message
        _inDesiredState = $false
    }
    
    $jsonOutput = $errorOutput | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput
    
    exit 0
}