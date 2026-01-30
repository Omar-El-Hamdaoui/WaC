param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

function Test-ScoopInstalled {
    $scoopPath = Get-ScoopPath
    return [bool]$scoopPath
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
    
    # A remettre cette ligne plus tard
    # Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"

    $scoopScript = Invoke-RestMethod get.scoop.sh
    Invoke-Expression "& {$scoopScript} -RunAsAdmin"
}


