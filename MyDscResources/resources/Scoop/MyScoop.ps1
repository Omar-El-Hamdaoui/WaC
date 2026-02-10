param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

function Test-ScoopInstalled {
    $scoopPath = Get-ScoopPath
    return [bool]$scoopPath
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
            name   = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
            ensure = if ($isInstalled) { 'Present' } else { 'Absent' }
        }
        
        return $state
    }
    catch {
        # En cas d'erreur, retourner un état minimal valide
        return @{
            name   = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
            ensure = 'Absent'
            error  = $_.Exception.Message
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
            name            = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
            ensure          = 'Absent'
            _inDesiredState = $false
            error           = $_.Exception.Message
        }
    }
}

function Set-ResourceState {
    param($InputObject)


    if(! (Test-ScoopInstalled)){

        $installerPath = Join-Path $env:TEMP "scoop-install-$(New-Guid).ps1"

        Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installerPath

        & $installerPath
    }

    else {
        #scoop uninstall scoop --purge
        Remove-Item -Recurse -Force ~\scoop
    }    
}

try {
    $result = switch ($Operation) {
        'Get' { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set' { Set-ResourceState -InputObject $inputObject }
    }

    $jsonOutput = $result | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput

    exit 0
}
catch {
    $errorOutput = @{
        name            = if ($inputObject.name) { $inputObject.name } else { 'Scoop' }
        ensure          = 'Absent'
        error           = $_.Exception.Message
        _inDesiredState = $false
    }

    $jsonOutput = $errorOutput | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput

    exit 0
}