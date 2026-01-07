param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

# Lecture de l'entrée JSON depuis stdin
$inputJson = [Console]::In.ReadToEnd()
$inputObject = if ($inputJson) { 
    $inputJson | ConvertFrom-Json 
} else { 
    @{ name = 'Chocolatey'; ensure = 'Present' } 
}

#region Helper Functions

function Test-ChocolateyInstalled {
    return (Test-Path "$env:ProgramData\chocolatey\choco.exe")
}

#endregion

#region DSC Operations

function Get-ResourceState {
    param($InputObject)
    
    $isInstalled = Test-ChocolateyInstalled
    
    $state = @{
        name = if ($InputObject.name) { $InputObject.name } else { 'Chocolatey' }
        ensure = if ($isInstalled) { 'Present' } else { 'Absent' }
    }
    
    # Ajouter des infos supplémentaires si installé
    if ($isInstalled) {
        $chocoVersion = & "$env:ProgramData\chocolatey\choco.exe" --version 2>$null
        if ($chocoVersion) {
            $state.version = $chocoVersion.Trim()
        }
        $state.installPath = "$env:ProgramData\chocolatey"
    }
    
    return $state
}

function Test-ResourceState {
    param($InputObject)
    
    $currentState = Get-ResourceState -InputObject $InputObject
    $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
    
    $inDesiredState = ($currentState.ensure -eq $desiredEnsure)
    
    $currentState._inDesiredState = $inDesiredState
    return $currentState
}

function Set-ResourceState {
    param($InputObject)
    
    $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
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
                    $installScript = Invoke-RestMethod -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing
                    Invoke-Expression $installScript
                    
                    # Rafraîchir PATH
                    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + 
                                [System.Environment]::GetEnvironmentVariable('Path', 'User')
                }
                catch {
                    throw "Failed to install Chocolatey: $_"
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
                            $value = [System.Environment]::GetEnvironmentVariable($envVar, $scope)
                            if ($value) {
                                [System.Environment]::SetEnvironmentVariable($envVar, $null, $scope)
                            }
                        }
                    }
                    
                    # Nettoyer PATH
                    foreach ($scope in $scopes) {
                        $path = [System.Environment]::GetEnvironmentVariable('Path', $scope)
                        if ($path) {
                            $newPath = ($path -split ';' | Where-Object { $_ -notlike '*chocolatey*' }) -join ';'
                            [System.Environment]::SetEnvironmentVariable('Path', $newPath, $scope)
                        }
                    }
                }
                catch {
                    throw "Failed to uninstall Chocolatey: $_"
                }
            }
        }
    }
    
    # Retourner le nouvel état
    return Get-ResourceState -InputObject $InputObject
}

#endregion

# Exécution de l'opération
try {
    $result = switch ($Operation) {
        'Get'  { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set'  { Set-ResourceState -InputObject $inputObject }
    }
    
    # Sortie en JSON
    $result | ConvertTo-Json -Compress
}
catch {
    $errorOutput = @{
        error = @{
            message = $_.Exception.Message
            type = $_.Exception.GetType().FullName
        }
    }
    [Console]::Error.WriteLine(($errorOutput | ConvertTo-Json -Compress))
    exit 1
}