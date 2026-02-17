param(
    [Parameter(Position = 0)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation = 'Get'
)

function Test-ScoopBucketInstalled { 
    param($InputObject) 
    try { 
        $buckets = scoop bucket list 
        return $buckets.name -contains $InputObject.name 
    } 
    catch {
         return $false 
    } 
}



function Get-ResourceState {
    param($InputObject)
    
    $name = $InputObject.name
    $isInstalled = Test-ScoopBucketInstalled -InputObject $inputObject

    return @{ 
        name = $name 
        ensure = if ($isInstalled) { 'Present' } else { 'Absent' } 
    } 
}


function Test-ResourceState {
    param($InputObject)
    $currentState = Get-ResourceState -InputObject $inputObject
    $desiredEnsure = if ($InputObject.ensure) { $InputObject.ensure } else { 'Present' }

    $inDesiredState = ($currentState.ensure -eq $desiredEnsure) 

    $currentState._inDesiredState = $inDesiredState

    return $currentState
}

function Set-ResourceState {
    param($InputObject)

    $ensure = $InputObject.ensure ?? 'Present'

    if ($ensure -eq 'Present') { 
        scoop bucket add $InputObject.name
    } 
    else {
        scoop bucket rm $InputObject.name 
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