[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation
)

function Get-WindowsDefenderExclusionState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $name = if ($InputObject.Name) { $InputObject.Name } else { 'WindowsDefenderPreference' }
    $type = $InputObject.Type
    $value = $InputObject.Value
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $currentEnsure = 'Absent'
    
    try {
        $preference = Get-MpPreference
        $exclusionProperty = "Exclusion$type"
        $exclusions = $preference.$exclusionProperty

        if ($exclusions -contains $value)
        {
            $currentEnsure = 'Present'
        }
    }
    catch {
        Write-Verbose "Error getting Windows Defender preferences: $_"
    }

    return [PSCustomObject]@{
        Name = $name
        Type = $type
        Value = $value
        Ensure = $currentEnsure
    }
}

function Test-WindowsDefenderExclusionState {
    param($InputObject)
    
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    $current = Get-WindowsDefenderExclusionState -InputObject $InputObject
    
    return $current.Ensure -eq $ensure
}

function Set-WindowsDefenderExclusionState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $type = $InputObject.Type
    $value = $InputObject.Value
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $parameterName = "Exclusion$type"
    $parameters = @{
        $parameterName = $value
    }

    try {
        if ($ensure -eq 'Present')
        {
            Add-MpPreference @parameters
        }
        elseif ($ensure -eq 'Absent')
        {
            Remove-MpPreference @parameters
        }
    }
    catch {
        Write-Error "Error modifying Windows Defender exclusion: $_"
        throw
    }
    
    return Get-WindowsDefenderExclusionState -InputObject $InputObject
}

# Main execution - Lecture depuis stdin
try {
    $jsonInput = [Console]::In.ReadToEnd()
    $inputObject = $jsonInput | ConvertFrom-Json

    $result = switch ($Operation) {
        'Get' { Get-WindowsDefenderExclusionState -InputObject $inputObject }
        'Test' { 
            $testResult = Test-WindowsDefenderExclusionState -InputObject $inputObject
            # Pour l'opération Test, on doit retourner l'état actuel avec la propriété InDesiredState
            $currentState = Get-WindowsDefenderExclusionState -InputObject $inputObject
            $currentState | Add-Member -MemberType NoteProperty -Name 'InDesiredState' -Value $testResult -Force
            $currentState
        }
        'Set' { Set-WindowsDefenderExclusionState -InputObject $inputObject }
    }

    # Sortie JSON avec profondeur suffisante
    Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}