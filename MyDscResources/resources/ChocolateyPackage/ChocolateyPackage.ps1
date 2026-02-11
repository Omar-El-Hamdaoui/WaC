param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)


# Read input from stdin
$inputJson = [Console]::In.ReadToEnd()
$inputObject = if ($inputJson) { 
    try {
        $inputJson | ConvertFrom-Json 
    }
    catch {
        # Fournit un objet par défaut pour éviter les erreurs de référence si l'entrée JSON est vide
        @{ packageName = ''; ensure = 'Present'; version = 'latest' }
    }
}
else { 
    @{ packageName = ''; ensure = 'Present'; version = 'latest' } 
}

# Chemin vers l'exécutable Chocolatey
$script:ChocoExe = "$env:ProgramData\chocolatey\choco.exe"

# Cache
$script:PackageListCache = $null
$script:PackageListCacheTime = $null
$script:OutdatedCache = $null
$script:OutdatedCacheTime = $null
$script:CacheDuration = [timespan]::FromMinutes(5)

#region Helper Functions

function Test-ChocolateyAvailable {
    try {
        # Vérifie si l'exécutable Choco est accessible dans le chemin d'installation standard ou dans le PATH
        if (Test-Path $script:ChocoExe) {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-ChocolateyPackageList {
    # Utilise le cache pour accélérer les opérations successives
    if ($script:PackageListCache -and 
        $script:PackageListCacheTime -and 
        ((Get-Date) - $script:PackageListCacheTime) -lt $script:CacheDuration) {
        return $script:PackageListCache
    }

    $packages = @{}
    
    try {
        $chocoList = & $script:ChocoExe list --local --limit-output 2>&1 | Out-String
        
        foreach ($line in $chocoList -split "`r?`n") {
            if ($line -match '^([^|]+)\|(.+)$') {
                $pkgName = $matches[1].Trim()
                $pkgVersion = $matches[2].Trim()
                
                if ($pkgName -and $pkgName -ne 'chocolatey') {
                    $packages[$pkgName] = $pkgVersion
                }
            }
        }
        
        $script:PackageListCache = $packages
        $script:PackageListCacheTime = Get-Date
    }
    catch {
        # Retourne un hashtable vide en cas d'erreur
    }
    
    return $packages
}

function Get-ChocolateyOutdatedPackages {
    # Utilise le cache pour accélérer les opérations successives
    if ($script:OutdatedCache -and 
        $script:OutdatedCacheTime -and 
        ((Get-Date) - $script:OutdatedCacheTime) -lt $script:CacheDuration) {
        return $script:OutdatedCache
    }

    $outdated = @{}
    
    try {
        $chocoOutdated = & $script:ChocoExe outdated --limit-output 2>&1 | Out-String
        
        foreach ($line in $chocoOutdated -split "`r?`n") {
            # Format: package|current|available|pinned
            if ($line -match '^([^|]+)\|([^|]+)\|([^|]+)\|') {
                $pkgName = $matches[1].Trim()
                $latestVersion = $matches[3].Trim()
                $outdated[$pkgName] = $latestVersion
            }
        }
        
        $script:OutdatedCache = $outdated
        $script:OutdatedCacheTime = Get-Date
    }
    catch {
        # Retourne un hashtable vide en cas d'erreur
    }
    
    return $outdated
}

function Get-PackageInfo {
    param([string]$PackageName)
    
    if (-not (Test-ChocolateyAvailable)) {
        return @{
            packageName      = $PackageName
            ensure           = 'Absent'
            installedVersion = $null
            latestVersion    = $null
            state            = 'ChocolateyNotInstalled'
        }
    }
    
    $installedPackages = Get-ChocolateyPackageList
    $outdatedPackages = Get-ChocolateyOutdatedPackages
    
    $info = @{
        packageName      = $PackageName
        ensure           = 'Absent'
        installedVersion = $null
        latestVersion    = $null
        state            = 'NotInstalled'
    }
    
    if ($installedPackages.ContainsKey($PackageName)) {
        $info.ensure = 'Present'
        $info.installedVersion = $installedPackages[$PackageName]
        
        if ($outdatedPackages.ContainsKey($PackageName)) {
            $info.latestVersion = $outdatedPackages[$PackageName]
            $info.state = 'Stale'
        }
        else {
            $info.latestVersion = $info.installedVersion
            $info.state = 'Current'
        }
    }
    # Si ensure est Absent, l'état reste NotInstalled
    
    return $info
}

#endregion

#region DSC Operations

function Get-ResourceState {
    param($InputObject)
    try {
        $packageName = $InputObject.packageName
        
        if (-not $packageName) {
            throw "packageName is required"
        }
        
        $info = Get-PackageInfo -PackageName $packageName
        
        # Ajout de la version désirée au résultat pour le mapping
        $info.version = if ($InputObject.version) { $InputObject.version } else { 'latest' }
        
        return $info
    }
    catch {
        return @{
            packageName      = $InputObject.packageName
            ensure           = 'Absent'
            version          = 'latest'
            installedVersion = $null
            latestVersion    = $null
            state            = 'Error'
            error            = $_.Exception.Message
        }
    }
}

function Test-ResourceState {
    param($InputObject)
    
    $logEntry = @{
        message = "Hello from Test-ResourceState "
        level   = "error"
    }
    
    $jsonLog = $logEntry | ConvertTo-Json -Compress
    [Console]::Error.WriteLine($jsonLog)

    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
        $desiredVersion = if ($InputObject.version) { $InputObject.version } else { 'latest' }
        
        $inDesiredState = $false
        
        if ($desiredEnsure -eq 'Absent') {
            $inDesiredState = ($currentState.ensure -eq 'Absent')
        }
        elseif ($desiredEnsure -eq 'Present') {
            if ($currentState.ensure -eq 'Absent') {
                $inDesiredState = $false
            }
            elseif ($currentState.state -eq 'ChocolateyNotInstalled') {
                $inDesiredState = $false
            }
            elseif ($desiredVersion -eq 'latest') {
                # Un package est dans l'état souhaité (latest) seulement s'il est 'Current'
                $inDesiredState = ($currentState.state -eq 'Current')
            }
            else {
                # Version spécifique demandée
                $inDesiredState = ($currentState.installedVersion -eq $desiredVersion)
            }
        }
        
        $currentState._inDesiredState = $inDesiredState
        return $currentState
    }
    catch {
        return @{
            packageName     = $InputObject.packageName
            ensure          = 'Absent'
            version         = 'latest'
            _inDesiredState = $false
            error           = $_.Exception.Message
        }
    }
}

function Set-ResourceState {
    param($InputObject)

    $logEntry = @{
        message = "Hello from Set-ResourceState "
        level   = "error"
    }
    
    $jsonLog = $logEntry | ConvertTo-Json -Compress
    [Console]::Error.WriteLine($jsonLog)
    
    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
        $desiredVersion = if ($InputObject.version) { $InputObject.version } else { 'latest' }
        
        if (-not (Test-ChocolateyAvailable)) {
            throw "Chocolatey is not installed. Please install Chocolatey first."
        }
        
        # Si le package est déjà dans l'état souhaité (Current pour latest), ne rien faire
        $testResult = Test-ResourceState -InputObject $InputObject
        if ($testResult._inDesiredState -and $currentState.ensure -ne 'Absent') {
            return $testResult # Sortie rapide si Current
        }
        
        $chocoArgs = @('-y', '--no-progress', '--limit-output')
        $commandOutput = ""
        
        if ($desiredEnsure -eq 'Present') {
            
            # 1. Installation si Absent
            if ($currentState.ensure -eq 'Absent') {
                $action = 'install'
                $argsList = @($InputObject.packageName) + $chocoArgs
                if ($desiredVersion -ne 'latest') {
                    $argsList += "--version"
                    $argsList += $desiredVersion
                }
                $commandOutput = & $script:ChocoExe $action $argsList *>&1 | Out-String
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Installation failed (Exit code $LASTEXITCODE). Output: `n$commandOutput"
                }
            }
            
            # 2. Upgrade si Stale (uniquement si 'latest' est demandé)
            elseif ($desiredVersion -eq 'latest' -and $currentState.state -eq 'Stale') {
                $action = 'upgrade'
                $argsList = @($InputObject.packageName) + $chocoArgs
                $commandOutput = & $script:ChocoExe $action $argsList *>&1 | Out-String
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Upgrade failed (Exit code $LASTEXITCODE). Output: `n$commandOutput"
                }
            }
            
            # 3. Réinstallation forcée pour une version spécifique différente
            elseif ($desiredVersion -ne 'latest' -and $currentState.installedVersion -ne $desiredVersion) {
                # Pour changer de version, il faut forcer l'installation
                $action = 'install'
                $argsList = @($InputObject.packageName, '--force') + $chocoArgs
                $argsList += "--version"
                $argsList += $desiredVersion
                
                $commandOutput = & $script:ChocoExe $action $argsList *>&1 | Out-String
                
                if ($LASTEXITCODE -ne 0) {
                    throw "Installation/Downgrade failed (Exit code $LASTEXITCODE). Output: `n$commandOutput"
                }
            }
        }
        else {
            # Désinstallation si Present
            & $script:ChocoExe uninstall $InputObject.packageName  $chocoArgs
        }
        
        # Invalidate caches pour lire le nouvel état
        $script:PackageListCache = $null
        $script:OutdatedCache = $null

    }
    catch {
        $errorState = Get-ResourceState -InputObject $InputObject
        # Ajout de l'erreur
        $errorState.error = $_.Exception.Message
        return $errorState
    }
}
#endregion

# Execute operation - Ensure ONLY JSON is output
try {
    $result = switch ($Operation) {
        'Get' { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set' { Set-ResourceState -InputObject $inputObject }
    }
    
    # Force clean JSON output
    $jsonOutput = $result | ConvertTo-Json -Compress -Depth 10
    [Console]::Out.WriteLine($jsonOutput)
    exit 0
}
catch {
    $errorOutput = @{
        packageName     = $inputObject.packageName
        ensure          = 'Absent'
        error           = $_.Exception.Message
        _inDesiredState = $false
    }
    
    $jsonOutput = $errorOutput | ConvertTo-Json -Compress -Depth 10
    [Console]::Out.WriteLine($jsonOutput)
    exit 0
}