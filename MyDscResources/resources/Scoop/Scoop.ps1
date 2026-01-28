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

# function Set-ResourceState {
#     param($InputObject)

    #   return @{
    #         name = 'Scoop'
    #         ensure = 'TITI'
    #     }

    # # Si déjà dans l'état désiré, ne rien faire
    # $testResult = Test-ResourceState -InputObject $InputObject
    # if ($testResult._inDesiredState) {
    #     return Get-ResourceState -InputObject $InputObject
    # }

    # $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }

    # if ($desiredEnsure -eq 'Present') {
    #     Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"
    #     #Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    #     #Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
       
    #     $isScoopInstalled = Test-ScoopInstalled

    #     if (-not $isScoopInstalled) {
    #         throw "Failed to install Scoop."
    #     }        

    # }
    # elseif ($desiredEnsure -eq 'Absent') {
    #     scoop uninstall scoop --purge
    #     # Remove-Item -Recurse -Force ~\scoop
    # }

    # return Get-ResourceState -InputObject $InputObject
# }

function Set-ResourceState {
    param($InputObject)
    
    #Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"
    
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression


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