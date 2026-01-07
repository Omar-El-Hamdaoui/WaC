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
    $line = "[$timestamp] [$env:USERNAME] $Message"
    try { Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue } catch {}
}

function Get-ScoopPaths {
    $homeDir = [System.Environment]::GetFolderPath('UserProfile')
    return @{
        Root       = Join-Path $homeDir "scoop"
        Apps       = Join-Path $homeDir "scoop\apps\scoop\current"
        Buckets    = Join-Path $homeDir "scoop\buckets"
        MainBucket = Join-Path $homeDir "scoop\buckets\main"
        Shims      = Join-Path $homeDir "scoop\shims"
        CoreScript = Join-Path $homeDir "scoop\apps\scoop\current\bin\scoop.ps1"
    }
}

function Get-ResourceState {
    param($InputObject)
    $paths = Get-ScoopPaths
    
    # VERIFICATION STRICTE
    # 1. Le script principal doit être là
    $hasCore = Test-Path $paths.CoreScript
    # 2. Le catalogue principal (bucket main) doit être là
    $hasBucket = Test-Path $paths.MainBucket

    Write-Trace "GET Check: Core=$hasCore Bucket=$hasBucket"

    # Si l'un des deux manque, on considère que Scoop est ABSENT (et donc cassé)
    $isHealthy = $hasCore -and $hasBucket

    return @{
        name = 'Scoop'
        ensure = if ($isHealthy) { 'Present' } else { 'Absent' }
        installPath = if ($isHealthy) { $paths.Root } else { $null }
    }
}

function Test-ResourceState {
    param($InputObject)
    $currentState = Get-ResourceState -InputObject $InputObject
    $desiredEnsure = $InputObject.ensure ?? 'Present'
    return @{
        name = 'Scoop'
        ensure = $currentState.ensure
        _inDesiredState = ($currentState.ensure -eq $desiredEnsure)
    }
}

function Set-ResourceState {
    param($InputObject)
    $desiredEnsure = $InputObject.ensure ?? 'Present'
    $paths = Get-ScoopPaths
    
    Write-Trace "SET Start: Desired='$desiredEnsure'"
    $currentState = Get-ResourceState -InputObject $InputObject

    if ($currentState.ensure -ne $desiredEnsure) {
        if ($desiredEnsure -eq 'Present') {
            
            # 1. NETTOYAGE PRÉALABLE
            Write-Trace "PRE-INSTALL: Cleaning corrupted installation..."
            $null = cmd.exe /c "rmdir /s /q `"$($paths.Root)`" 2>NUL"
            $null = cmd.exe /c "rmdir /s /q `"$($env:UserProfile)\.config\scoop`" 2>NUL"
            Start-Sleep -Milliseconds 500

            # 2. INSTALLATION MANUELLE (GOD MODE)
            Write-Trace "SET Action: Installing Scoop & Buckets..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            try {
                # A. Création structure
                New-Item -ItemType Directory -Path $paths.Apps -Force | Out-Null
                New-Item -ItemType Directory -Path $paths.Buckets -Force | Out-Null
                New-Item -ItemType Directory -Path $paths.Shims -Force | Out-Null
                New-Item -ItemType Directory -Path "$($paths.Root)\cache" -Force | Out-Null
                New-Item -ItemType Directory -Path "$($paths.Root)\persist" -Force | Out-Null

                # B. Moteur Scoop (Core)
                $zipUrl = "https://github.com/ScoopInstaller/Scoop/archive/master.zip"
                $zipPath = Join-Path $env:TEMP "scoop_core.zip"
                Write-Trace "SET Download: Core..."
                Invoke-RestMethod -Uri $zipUrl -OutFile $zipPath
                
                Expand-Archive -Path $zipPath -DestinationPath "$env:TEMP\scoop_extract" -Force
                $sourceContent = Join-Path "$env:TEMP\scoop_extract" "Scoop-master"
                Copy-Item -Path "$sourceContent\*" -Destination $paths.Apps -Recurse -Force

                # C. Bucket Main (Catalogue)
                $bucketUrl = "https://github.com/ScoopInstaller/Main/archive/master.zip"
                $bucketZip = Join-Path $env:TEMP "scoop_main.zip"
                Write-Trace "SET Download: Main Bucket..."
                Invoke-RestMethod -Uri $bucketUrl -OutFile $bucketZip
                
                Expand-Archive -Path $bucketZip -DestinationPath "$env:TEMP\bucket_extract" -Force
                $bucketSource = Join-Path "$env:TEMP\bucket_extract" "Main-master"
                $bucketDest = Join-Path $paths.Buckets "main"
                
                if (Test-Path $bucketDest) { Remove-Item $bucketDest -Recurse -Force }
                Move-Item -Path $bucketSource -Destination $bucketDest -Force

                # D. Reset (Génération Shims)
                Write-Trace "SET Init: Running 'scoop reset'..."
                $currentExe = (Get-Process -Id $PID).Path
                $scoopScriptPath = $paths.CoreScript
                
                # Correction syntaxe commande
                $resetCmd = "& '$scoopScriptPath' reset"

                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $currentExe
                $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$resetCmd`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true

                $p = [System.Diagnostics.Process]::Start($psi)
                $p.WaitForExit()
                
                $stdout = $p.StandardOutput.ReadToEnd()
                Write-Trace "SET Init Output: $stdout"

                # Nettoyage
                Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                Remove-Item $bucketZip -Force -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP\scoop_extract" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item "$env:TEMP\bucket_extract" -Recurse -Force -ErrorAction SilentlyContinue

            }
            catch {
                Write-Trace "SET ERROR: $($_.Exception.Message)"
                throw "Erreur installation : $_"
            }

            if (-not (Test-Path $paths.MainBucket)) { throw "Install failed: Main bucket missing" }
        }
        elseif ($desiredEnsure -eq 'Absent') {
             $null = cmd.exe /c "rmdir /s /q `"$($paths.Root)`" 2>NUL"
        }
    }
    return Get-ResourceState -InputObject $InputObject
}

# --- MAIN ---
try {
    $inputJson = [Console]::In.ReadToEnd()
    $inputObject = $inputJson ? ($inputJson | ConvertFrom-Json) : @{ ensure = 'Present' }
    $result = switch ($Operation) {
        'Get'  { Get-ResourceState -InputObject $inputObject }
        'Test' { Test-ResourceState -InputObject $inputObject }
        'Set'  { Set-ResourceState -InputObject $inputObject }
    }
    Write-Output ($result | ConvertTo-Json -Compress -Depth 10)
    exit 0
}
catch {
    Write-Trace "FATAL: $($_.Exception.Message)"
    $err = @{ name='Scoop'; ensure='Absent'; error=$_.Exception.Message; _inDesiredState=$false }
    Write-Output ($err | ConvertTo-Json -Compress)
    exit 0
}