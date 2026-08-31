param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

. $PSScriptRoot\MyNodeVersion.Helpers.ps1

function Get-ResourceState {
    param($InputObject)

    $version = $InputObject.version

    if (-not ($version -in @('lts', 'latest') -or $version -match '^\d+$')) {
        throw "Version must be 'lts', 'latest', or an integer representing the major version."
    }

    $current = @{
        version        = $version
        ensure         = 'Absent'
        currentVersion = $null
        latestVersion  = $null
        state          = 'Unknown'
    }

    $latestVersions = Get-NodeLatestVersions

    if ($version -in 'lts', 'latest') {
        $current.latestVersion = $latestVersions[$version]
        $majorVersion = $current.latestVersion -replace '\.\d+\.\d+$', ''
    }
    else {
        $majorVersion = [int]($version -split '\.')[0]

        if (-not $latestVersions.ContainsKey($majorVersion)) {
            throw "Major version $majorVersion is not available."
        }

        $current.latestVersion = $latestVersions[$majorVersion]
    }

    $nvmInstalledVersions = Get-NvmInstalledVersions

    $versionInstalled = $nvmInstalledVersions |
    Where-Object { $_.StartsWith("$majorVersion.") } |
    Select-Object -First 1

    if ($null -eq $versionInstalled) {
        return $current
    }

    $current.currentVersion = $versionInstalled

    $nvmCurrentVersion = Get-NvmCurrentVersion

    $current.ensure = $nvmCurrentVersion -eq $current.latestVersion ? 'Used' : 'Present'
    $current.state = $current.currentVersion -eq $current.latestVersion ? 'Current' : 'Stale'

    return $current
}

function Test-ResourceState {
    param($InputObject)

    $currentState = Get-ResourceState -InputObject $InputObject
    $desiredEnsure = $InputObject.ensure

    if ($desiredEnsure -eq 'Absent') {
        $currentState._inDesiredState = $currentState.ensure -eq $desiredEnsure

        return $currentState
    }

    if ($currentState.ensure -eq 'Absent') {
        $currentState._inDesiredState = $false

        return $currentState
    }

    if ($desiredEnsure -eq 'Used' -and $currentState.ensure -ne $desiredEnsure) {
        $currentState._inDesiredState = $false

        return $currentState
    }

    $currentState._inDesiredState = $currentState.latestVersion -eq $currentState.currentVersion

    return $currentState
}


function Set-ResourceState {
    param($InputObject)

    $testResult = Test-ResourceState -InputObject $InputObject

    if ($testResult._inDesiredState) {
        return
    }

    $ensure = $InputObject.ensure

    if ($ensure -eq 'Absent') {
        if ($testResult.ensure -ne 'Absent') {
            & nvm uninstall $testResult.currentVersion
        }

        return
    }

    if ($testResult.ensure -eq 'Absent' -or $testResult.currentVersion -ne $testResult.latestVersion) {
        & nvm install $testResult.latestVersion
    }

    if ($ensure -eq 'Used') {
        & nvm use $testResult.latestVersion
    }

    # Cleanup old unused versions
    $nvmStaleVersions = Get-NvmStaleVersions
    $nvmCurrentVersion = Get-NvmCurrentVersion
    $versionsToRemove = $nvmStaleVersions | Where-Object { $_ -ne $nvmCurrentVersion }

    $versionsToRemove | ForEach-Object {
        & nvm uninstall $_
    }
}


try {
    $inputJson = [Console]::In.ReadToEnd()
    $inputObject = $inputJson | ConvertFrom-Json

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
    $errorJson = @{
        message   = $_.Exception.Message
        operation = $Operation
        level     = "error"
    } | ConvertTo-Json -Compress

    Write-Error $errorJson
    exit 1
}