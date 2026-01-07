param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

$nvmPath = "$env:USERPROFILE\scoop\shims\nvm.cmd"
if (-not (Test-Path $nvmPath)) {
    $nvmPath = "$env:USERPROFILE\scoop\apps\nvm\current\nvm.exe"
}
if (-not (Test-Path $nvmPath)) {
    # Essayer le chemin global
    $nvmPath = "C:\ProgramData\scoop\shims\nvm.cmd"
}

# Créer une fonction wrapper pour nvm
function Invoke-Nvm {
    param([Parameter(ValueFromRemainingArguments)]$Arguments)
    & $nvmPath @Arguments
}
Set-Alias -Name nvm -Value Invoke-Nvm -Scope Script

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Lecture entrée JSON
$inputJson = [Console]::In.ReadToEnd()
$inputObject = if ($inputJson) { 
    try { $inputJson | ConvertFrom-Json }
    catch { @{ version = 'lts'; ensure = 'Present' } }
} else { @{ version = 'lts'; ensure = 'Present' } }

# Cache
$script:nodeLatestVersionsCache = $null
$script:LastNodeLatestVersionsRefreshed = $null
$script:CacheDurationMinutes = 5

#region Helper Functions
function Get-NvmInstalledVersions {
    $nvmList = & nvm list
    $installedVersions = $nvmList -split '\r?\n' |
        Where-Object { $_.Trim() -ne '' } |
        ForEach-Object {
            if ($_ -match '\d+\.\d+\.\d+') {
                $matches[0] 
            }
        }
    return $installedVersions
}

function Get-NvmCurrentVersion {
    return (nvm current) -Replace '^v'
}

function Get-NvmStaleVersions {
    $installedVersions = Get-NvmInstalledVersions
    $latestVersions = @{}
    $staleVersions = @()

    foreach ($version in $installedVersions) {
        $splitVersion = $version -split '\.'
        $majorVersion = [int]$splitVersion[0]
        $minorVersion = [int]$splitVersion[1]
        $patchVersion = [int]$splitVersion[2]

        if ($latestVersions.ContainsKey($majorVersion)) {
            $latestSplitVersion = $latestVersions[$majorVersion] -split '\.'
            $latestMinorVersion = [int]$latestSplitVersion[1]
            $latestPatchVersion = [int]$latestSplitVersion[2]

            if (($minorVersion -gt $latestMinorVersion) -or (($minorVersion -eq $latestMinorVersion) -and ($patchVersion -gt $latestPatchVersion))) {
                $staleVersions += $latestVersions[$majorVersion]
                $latestVersions[$majorVersion] = $version
            }
            else {
                $staleVersions += $version
            }
        }
        else {
            $latestVersions[$majorVersion] = $version
        }
    }
    return $staleVersions
}

function Get-NodeLatestVersions {
    if (-not $script:nodeLatestVersionsCache -or (Get-Date) -gt $script:LastNodeLatestVersionsRefreshed.AddMinutes($script:CacheDurationMinutes)) {
        try {
            $url = 'https://nodejs.org/dist/index.json'
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing
            $nodeVersions = $resp.Content | ConvertFrom-Json

            $versionsHashTable = @{}
            $latestVersion = $null
            $latestLts = $null

            foreach ($item in $nodeVersions) {
                if ($item.version -match '^v(.+)$') {
                    $versionString = $Matches[1]
                    $version = [version]$versionString
                    $majorVersion = $version.Major

                    if ($null -eq $latestVersion -or $version -gt [version]$latestVersion) {
                        $latestVersion = $versionString
                    }

                    if ($item.lts -and ($null -eq $latestLts -or $version -gt [version]$latestLts)) {
                        $latestLts = $versionString
                    }

                    if (-not $versionsHashTable.ContainsKey($majorVersion) -or $version -gt [version]$versionsHashTable[$majorVersion]) {
                        $versionsHashTable[$majorVersion] = $versionString
                    }
                }
            }
 
            $versionsHashTable['latest'] = $latestVersion
            $versionsHashTable['lts'] = $latestLts

            $script:nodeLatestVersionsCache = $versionsHashTable
            $script:LastNodeLatestVersionsRefreshed = Get-Date
        }
        catch {
            throw "Failed to retrieve Node.js versions: $_"
        }
    }
    return $script:nodeLatestVersionsCache
}
#endregion

#region DSC Operations
function Get-ResourceState {
    param($InputObject)
    try {
        $version = $InputObject.version ?? 'lts'
        
        if (-not ($version -in @('lts', 'latest') -or $version -match '^\d+$')) {
            throw "Version must be 'lts', 'latest', or an integer (major version)"
        }

        $latestVersions = Get-NodeLatestVersions
        
        if ($version -in 'lts', 'latest') {
            $latestVersion = $latestVersions[$version]
            $majorVersion = $latestVersion -replace '\.\d+\.\d+$', ''
        }
        else {
            $majorVersion = [int]($version -split '\.')[0]
            if ($latestVersions.ContainsKey($majorVersion)) {
                $latestVersion = $latestVersions[$majorVersion]
            }
            else {
                throw "Major version $majorVersion not available"
            }
        }

        $nvmInstalledVersions = Get-NvmInstalledVersions
        $versionInstalled = $nvmInstalledVersions | Where-Object { $_.StartsWith("$majorVersion.") } | Select-Object -First 1
        
        $state = @{
            version       = $version
            latestVersion = $latestVersion
        }

        if ($null -ne $versionInstalled) {
            $state.currentVersion = $versionInstalled
            $nvmCurrentVersion = Get-NvmCurrentVersion
            $state.ensure = ($nvmCurrentVersion -eq $latestVersion) ? 'Used' : 'Present'
            $state.state = ($versionInstalled -eq $latestVersion) ? 'Current' : 'Stale'
        }
        else {
            $state.currentVersion = $null
            $state.ensure = 'Absent'
            $state.state = 'NotInstalled'
        }

        return $state
    }
    catch {
        return @{
            version = $InputObject.version ?? 'lts'
            ensure  = 'Absent'
            error   = $_.Exception.Message
        }
    }
}

function Test-ResourceState {
    param($InputObject)
    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        $desiredEnsure = $InputObject.ensure ?? 'Present'
        
        $inDesiredState = $false
        
        if ($desiredEnsure -eq 'Absent') {
            $inDesiredState = ($currentState.ensure -eq 'Absent')
        }
        elseif ($currentState.ensure -eq 'Absent') {
            $inDesiredState = $false
        }
        elseif ($desiredEnsure -eq 'Used' -and $currentState.ensure -ne 'Used') {
            $inDesiredState = $false
        }
        else {
            $inDesiredState = ($currentState.latestVersion -eq $currentState.currentVersion)
        }
        
        $currentState._inDesiredState = $inDesiredState
        return $currentState
    }
    catch {
        return @{
            version         = $InputObject.version ?? 'lts'
            ensure          = 'Absent'
            _inDesiredState = $false
            error           = $_.Exception.Message
        }
    }
}

function Set-ResourceState {
    param($InputObject)
    
    $desiredEnsure = $InputObject.ensure ?? 'Present'
    
    try {
        $currentState = Get-ResourceState -InputObject $InputObject
        $testResult = Test-ResourceState -InputObject $InputObject
        
        if ($testResult._inDesiredState) {
            return Get-ResourceState -InputObject $InputObject
        }
        
        if ($desiredEnsure -eq 'Absent') {
            if ($currentState.currentVersion) {
                & nvm uninstall $currentState.currentVersion *>&1 | Out-Null
            }
        }
        else {
            # Install if absent or outdated
            if ($currentState.ensure -eq 'Absent' -or $currentState.currentVersion -ne $currentState.latestVersion) {
                & nvm install $currentState.latestVersion *>&1 | Out-Null
            }
            
            # Use if required
            if ($desiredEnsure -eq 'Used') {
                & nvm use $currentState.latestVersion *>&1 | Out-Null
            }

            # Cleanup stale versions
            $nvmStaleVersions = Get-NvmStaleVersions
            $nvmCurrentVersion = Get-NvmCurrentVersion
            $versionsToRemove = $nvmStaleVersions | Where-Object { $_ -ne $nvmCurrentVersion }
            $versionsToRemove | ForEach-Object {
                & nvm uninstall $_ *>&1 | Out-Null
            }
        }
        
        return Get-ResourceState -InputObject $InputObject
    }
    catch {
        $errorState = Get-ResourceState -InputObject $InputObject
        $errorState.error = $_.Exception.Message
        return $errorState
    }
}
#endregion

# Exécution
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
        version         = $inputObject.version ?? 'lts'
        ensure          = 'Absent'
        error           = $_.Exception.Message
        _inDesiredState = $false
    }
    
    Write-Output ($errorOutput | ConvertTo-Json -Compress -Depth 10)
    exit 0
}