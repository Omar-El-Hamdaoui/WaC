param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

$ErrorActionPreference = 'Stop'

# --- DEBUG LOGGER ---
$logFile = Join-Path ([System.Environment]::GetFolderPath('Desktop')) "scoop_debug.log"

function Write-Trace {
    param($Message)
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] [PACKAGE] $Message" 
    try { Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Get-ScoopExecutable {
    $homeDir = [System.Environment]::GetFolderPath('UserProfile')
    $core = Join-Path $homeDir "scoop\apps\scoop\current\bin\scoop.ps1"
    if (Test-Path $core) { return $core }
    $shim = Join-Path $homeDir "scoop\shims\scoop.ps1"
    if (Test-Path $shim) { return $shim }
    return $null
}

function Invoke-Scoop {
    param($Command, $ArgsList)

    $scoopScript = Get-ScoopExecutable
    if (-not $scoopScript) { throw "Scoop is not installed." }

    $currentExe = (Get-Process -Id $PID).Path
    
    # On nettoie les arguments pour éviter les doubles quotes problématiques
    $fullArgs = "& `"$scoopScript`" $Command $ArgsList"
    
    Write-Trace "EXEC: Running '$Command $ArgsList'"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $currentExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$fullArgs`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $env:TEMP 

    # --- INJECTION PROXY DANS L'ENVIRONNEMENT DU PROCESSUS ---
    # C'est souvent plus efficace que 'scoop config proxy'
    try {
        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $proxyUri = $sysProxy.GetProxy("http://google.com").AbsoluteUri
        if ($proxyUri -and $proxyUri -ne "http://google.com/") {
            # On passe l'URL complète aux variables d'environnement standard
            $psi.EnvironmentVariables["HTTP_PROXY"] = $proxyUri
            $psi.EnvironmentVariables["HTTPS_PROXY"] = $proxyUri
            $psi.EnvironmentVariables["ALL_PROXY"] = $proxyUri
        }
    } catch {}
    # ---------------------------------------------------------

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    if ($stdout) { Write-Trace "OUT: $stdout" }
    if ($stderr) { Write-Trace "ERR: $stderr" }

    return $stdout
}

# --- DSC OPERATIONS ---

function Get-ResourceState {
    param($InputObject)
    $pkgName = $InputObject.packageName
    
    Write-Trace "GET: Checking '$pkgName'..."
    
    try {
        $jsonStr = Invoke-Scoop "export" ""
        
        $installed = $false
        $currentVersion = $null
        $isBroken = $false

        if ($jsonStr) {
            try {
                $data = $jsonStr | ConvertFrom-Json
                $appInfo = $data.apps | Where-Object { $_.Name -eq $pkgName }
                
                if ($appInfo) {
                    if ($appInfo.Info -match "failed") {
                        Write-Trace "WARN: '$pkgName' detected but marked as FAILED."
                        $isBroken = $true
                        $installed = $false 
                    }
                    else {
                        $installed = $true
                        $currentVersion = $appInfo.Version
                    }
                }
            } catch {
                Write-Trace "WARN: JSON parse failed."
            }
        }

        $state = @{
            packageName = $pkgName
            ensure = if ($installed) { 'Present' } else { 'Absent' }
            version = $InputObject.version ?? 'latest'
            installedVersion = $currentVersion
            _isBroken = $isBroken
        }

        return $state
    }
    catch {
        return @{ packageName = $pkgName; ensure = 'Absent' }
    }
}

function Test-ResourceState {
    param($InputObject)
    $currentState = Get-ResourceState -InputObject $InputObject
    $desiredEnsure = $InputObject.ensure ?? 'Present'
    
    $inDesired = ($currentState.ensure -eq $desiredEnsure)
    if ($inDesired -and $desiredEnsure -eq 'Present' -and $InputObject.version -ne 'latest' -and $InputObject.version) {
        $inDesired = ($currentState.installedVersion -eq $InputObject.version)
    }

    return @{
        packageName = $InputObject.packageName
        ensure = $currentState.ensure
        _inDesiredState = $inDesired
    }
}

function Set-ResourceState {
    param($InputObject)
    $pkgName = $InputObject.packageName
    $desiredEnsure = $InputObject.ensure ?? 'Present'
    $version = $InputObject.version ?? 'latest'
    
    Write-Trace "SET: Start for '$pkgName'"

    $currentState = Get-ResourceState -InputObject $InputObject

    if ($currentState.ensure -ne $desiredEnsure) {
        if ($desiredEnsure -eq 'Present') {
        
            Write-Trace "ACTION: Installing '$pkgName'..."
            
            if ($pkgName -ne '7zip') {
                try { Invoke-Scoop "install" "7zip" } catch {}
            }

            try {
                $installArg = $pkgName
                if ($version -ne 'latest') { $installArg = "$pkgName@$version" }
                
                Invoke-Scoop "install" "$installArg"
                Write-Trace "ACTION: Success."
            }
            catch {
                Write-Trace "ACTION FAILED: $($_.Exception.Message)"
                
                # PLAN B : Si ça échoue, on tente de supprimer le proxy de la config Scoop
                # et de laisser le système gérer (parfois mieux)
                Write-Trace "RETRY: Clearing Scoop proxy config and retrying..."
                try {
                    Invoke-Scoop "config" "rm proxy"
                    Invoke-Scoop "install" "$installArg"
                    Write-Trace "ACTION: Success on Retry."
                } catch {
                    throw "Failed to install $pkgName. Log: $_"
                }
            }
        }
        elseif ($desiredEnsure -eq 'Absent') {
            Write-Trace "ACTION: Uninstalling '$pkgName'..."
            try { Invoke-Scoop "uninstall" $pkgName } catch {}
        }
    }

    return Get-ResourceState -InputObject $InputObject
}

# --- MAIN ---
try {
    $inputJson = [Console]::In.ReadToEnd()
    $inputObject = $inputJson ? ($inputJson | ConvertFrom-Json) : @{ packageName = 'git'; ensure = 'Present' }

    $result = switch ($Operation) {
        'Get'  { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set'  { Set-ResourceState -InputObject $inputObject }
    }
    
    Write-Output ($result | ConvertTo-Json -Compress -Depth 10)
    exit 0
}
catch {
    $err = @{ packageName = $inputObject.packageName; ensure = 'Absent'; error = $_.Exception.Message; _inDesiredState = $false }
    Write-Output ($err | ConvertTo-Json -Compress)
    exit 0
}