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
        @{ name = 'OldScoop'; ensure = 'Present' }
    }
} else {
    @{ name = 'OldScoop'; ensure = 'Present' }
}

function Write-ErrorLog {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    $logEntry = @{
        message = $Message
        level   = "error"
    }

    $jsonLog = $logEntry | ConvertTo-Json -Compress
    [Console]::Error.WriteLine($jsonLog)
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

    $logEntry = @{

    message = "This is a call to Get-ResourceState."

    level = "error"

    }

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    # $logEntry = @{

    #     message = "=== GET-RESOURCESTATE: Début ==="

    #     level   = "error"

    # }

    # $jsonLog = $logEntry | ConvertTo-Json -Compress

    # [Console]::Error.WriteLine($jsonLog)


    $logEntry = @{

        message = "Input received: $($InputObject | ConvertTo-Json -Compress)"

        level   = "error"

    }

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    #Write-ErrorLog "=== GET-RESOURCESTATE: Début ==="
    #Write-ErrorLog "Input received: $($InputObject | ConvertTo-Json -Compress)"


    try {

        #Write-ErrorLog "GET: Appel de Test-ScoopInstalled..."
        $isInstalled = Test-ScoopInstalled
        #Write-ErrorLog "GET: Scoop installé ? $isInstalled"


        $isInstalled = Test-ScoopInstalled

        $state = @{
            name = if ($InputObject.name) { $InputObject.name } else { 'Scoop' }
            ensure = if ($isInstalled) { 'Present' } else { 'Absent' }
        }

        #Write-ErrorLog "GET: État de base créé - ensure=$($state.ensure)"



        # Ajouter des infos supplémentaires si installé
        if ($isInstalled) {

            #Write-ErrorLog "GET: Récupération de la version..."


            $version = Get-ScoopVersion
            if ($version) {
                $state.version = $version
                #Write-ErrorLog "GET: Version trouvée: $version"
            }

            #Write-ErrorLog "GET: Récupération du chemin..."
            $installPath = Get-ScoopPath
            if ($installPath) {
                $state.installPath = $installPath
                #Write-ErrorLog "GET: Chemin trouvé: $installPath"
            }
        }


        $logEntry = @{

        message = "=== GET-RESOURCESTATE: Fin ==="

        level = "error"

        }

        $jsonLog = $logEntry | ConvertTo-Json -Compress

        [Console]::Error.WriteLine($jsonLog)

     


        #Write-ErrorLog "GET: État final: $($state | ConvertTo-Json -Compress)"
        #Write-ErrorLog "=== GET-RESOURCESTATE: Fin ==="

        return $state
    }
    catch {

        $logEntry = @{

        message = "GET: ERREUR un état minimal valide sera retourné "

        level = "error"

        }
        $jsonLog = $logEntry | ConvertTo-Json -Compress

        [Console]::Error.WriteLine($jsonLog)


        # En cas d'erreur, retourner un état minimal valide
        return @{
            name = if ($InputObject.name) { $InputObject.name } else { 'OldScoop' }
            ensure = 'Absent'
            error = $_.Exception.Message
        }
    }
}

function Test-ResourceState {
    param($InputObject)

    $logEntry = @{

    message = "This is a call to Test-ResourceState."

    level = "error"

    }

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    #     $logEntry = @{

    #     message = "=== TEST-RESOURCESTATE: Début ==="

    #     level   = "error"

    # }
    # $jsonLog = $logEntry | ConvertTo-Json -Compress

    # [Console]::Error.WriteLine($jsonLog)


    #     $logEntry = @{

    #     message = "TEST: Input received: $($InputObject | ConvertTo-Json -Compress)"

    #     level   = "error"

    # }
    # $jsonLog = $logEntry | ConvertTo-Json -Compress

    # [Console]::Error.WriteLine($jsonLog)



    ##Write-ErrorLog "=== TEST-RESOURCESTATE: Début ==="
    ##Write-ErrorLog "TEST: Input received: $($InputObject | ConvertTo-Json -Compress)"

    try {
        ##Write-ErrorLog "TEST: Appel de Get-ResourceState..."
        $currentState = Get-ResourceState -InputObject $InputObject
        ##Write-ErrorLog "TEST: État actuel reçu: $($currentState | ConvertTo-Json -Compress)"
        
        $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }
        ##Write-ErrorLog "TEST: Ensure désiré: $desiredEnsure"
        ##Write-ErrorLog "TEST: Ensure actuel: $($currentState.ensure)"

        $inDesiredState = ($currentState.ensure -eq $desiredEnsure)
        ##Write-ErrorLog "TEST: Dans l'état désiré ? $inDesiredState"

        $currentState._inDesiredState = $inDesiredState
        
        ##Write-ErrorLog "TEST: Retour de l'état avec _inDesiredState=$inDesiredState"
        ##Write-ErrorLog "=== TEST-RESOURCESTATE: Fin ==="

        return $currentState
    }
    catch {
        ##Write-ErrorLog "TEST: ERREUR - $($_.Exception.Message)"
        ##Write-ErrorLog "TEST: StackTrace - $($_.ScriptStackTrace)"
        # Retourner un état avec erreur mais JSON valide
        return @{
            name = if ($InputObject.name) { $InputObject.name } else { 'OldScoop' }
            ensure = 'Absent'
            _inDesiredState = $false
            error = $_.Exception.Message
        }
    }
}



function Set-ResourceState {
    param($InputObject)

    
    $logEntry = @{

        message = "1"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    $logEntry = @{

        message = "2"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    $logEntry = @{

        message = "3"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    # $logEntry = @{

    # message = "This is a call to Set-ResourceState."

    # level = "error"

    # }

    # $jsonLog = $logEntry | ConvertTo-Json -Compress

    # [Console]::Error.WriteLine($jsonLog)


    $logEntry = @{

    message = "SET: Input received: $($InputObject | ConvertTo-Json -Compress)"

    level = "error"

    }

    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)
    
    
        $logEntry = @{

        message = "4"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)
    #Write-ErrorLog -Message "=== SET-RESOURCESTATE: APPELÉ ==="
    #Write-ErrorLog "SET: Input received: $($InputObject | ConvertTo-Json -Compress)"


    #Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"


    # Write-ErrorLog "SET: Téléchargement du script depuis get.scoop.sh..."

  
        $logEntry = @{

        message = "5"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    $installScript = Invoke-RestMethod get.scoop.sh


    $logEntry = @{

        message = "after 5"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)




    # $scriptLength = if ($null -eq $installScript) { 0 } else { $installScript.Length }

    # $logEntry = @{
    #     message = "SET: Script téléchargé ($scriptLength caractères)"
    #     level = "error"
    # }
    # $jsonLog = $logEntry | ConvertTo-Json -Compress
    # [Console]::Error.WriteLine($jsonLog)




    $logEntry = @{
    message = "after 5 - Script downloaded: $(if ($installScript) { 'OUI' } else { 'NON' })"
    level = "error"
    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    # $jsonState = if ($null -eq $installScript) { "null" } else { $installScript | ConvertTo-Json -Compress }


    # $logEntry = @{

    #     message = "SET: Script téléchargé $jsonState chars)"

    #     level = "error"

    # }
    # $jsonLog = $logEntry | ConvertTo-Json -Compress

    # [Console]::Error.WriteLine($jsonLog)

    $logEntry = @{

        message = "Before : Invoke-Expression"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    
    try{

    $output = Invoke-Expression "& {$installScript} -RunAsAdmin" 2>&1 | out-string 
    
    }
    catch{

        $logEntry = @{

            message = "After : Invoke-Expression output: $($_.Exception.Message)"

            level = "error"

        }
        $jsonLog = $logEntry | ConvertTo-Json -Compress

        [Console]::Error.WriteLine($jsonLog)

    }




    $logEntry = @{

        message = "After : Invoke-Expression output: $output"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    #    Write-ErrorLog "SET: Script téléchargé ($($installScript.Length) chars)"
    #     Write-ErrorLog "SET: Exécution avec -RunAsAdmin..."


    #     Write-ErrorLog "SET: Installation terminée !"


    #     Write-ErrorLog "SET: Vérification du nouvel état..."
        
    $finalState = Get-ResourceState -InputObject $InputObject



    #     Write-ErrorLog "SET: État final: $($finalState | ConvertTo-Json -Compress)"

    $logEntry = @{

        message = "6"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)



    $jsonState = if ($null -eq $finalState) { "null" } else { $finalState | ConvertTo-Json -Compress }

    $logEntry = @{

        message = "SET: État final: $jsonState"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)


    # Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    # Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression

    $logEntry = @{

        message = "$($finalState | ConvertTo-Json -Compress)"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)



        $logEntry = @{

        message = "7"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

    $logEntry = @{

        message = "=== SET-RESOURCESTATE: Fin ==="

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

        $logEntry = @{

        message = "8"

        level = "error"

    }
    $jsonLog = $logEntry | ConvertTo-Json -Compress

    [Console]::Error.WriteLine($jsonLog)

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
        name = if ($inputObject.name) { $inputObject.name } else { 'OldScoop' }
        ensure = 'Absent'
        error = $_.Exception.Message
        _inDesiredState = $false
    }

    $jsonOutput = $errorOutput | ConvertTo-Json -Compress -Depth 10
    Write-Output $jsonOutput

    exit 0
}