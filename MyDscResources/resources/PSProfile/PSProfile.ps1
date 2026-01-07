[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation
)

function Get-PSProfileState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $name = $InputObject.Name
    $path = $InputObject.Path
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $currentEnsure = 'Absent'
    
    $scriptHeader = "# WAC - $name"
    $scriptCall = ". '$path'"
    
    if (Test-ScriptInProfile -ExpectedScriptHeader $scriptHeader -ExpectedScriptCall $scriptCall)
    {
        $currentEnsure = 'Present'
    }

    return [PSCustomObject]@{
        Name = $name
        Path = $path
        Ensure = $currentEnsure
    }
}

function Test-PSProfileState {
    param($InputObject)
    
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    $current = Get-PSProfileState -InputObject $InputObject
    
    return $current.Ensure -eq $ensure
}

function Set-PSProfileState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $name = $InputObject.Name
    $path = $InputObject.Path
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $systemProfilePath = $global:PROFILE.CurrentUserAllHosts
    $scriptHeader = "# WAC - $name"
    $scriptCall = ". '$path'"
    
    if ($ensure -eq 'Present')
    {
        # Check if script is already in profile
        $isPresent = Test-ScriptInProfile -ExpectedScriptHeader $scriptHeader -ExpectedScriptCall $scriptCall
        
        if (-not $isPresent)
        {
            # Add the script to the profile
            $contentToAdd = "`n$scriptHeader`n$scriptCall`n"
            Add-Content -Path $systemProfilePath -Value $contentToAdd
        }
    }
    elseif ($ensure -eq 'Absent')
    {
        # Remove the script from the profile
        if (Test-Path -Path $systemProfilePath)
        {
            $profileContent = Get-Content -Path $systemProfilePath
            $newContent = @()
            $skipNext = $false
            
            foreach ($line in $profileContent)
            {
                if ($skipNext)
                {
                    $skipNext = $false
                    continue
                }
                
                if ($line -match [regex]::Escape($scriptHeader))
                {
                    $skipNext = $true
                    continue
                }
                
                $newContent += $line
            }
            
            Set-Content -Path $systemProfilePath -Value $newContent
        }
    }
    
    return Get-PSProfileState -InputObject $InputObject
}

function Test-ScriptInProfile {
    param(
        [string]$ExpectedScriptHeader,
        [string]$ExpectedScriptCall
    )
    
    $systemProfilePath = $global:PROFILE.CurrentUserAllHosts
    
    if (-not (Test-Path -Path $systemProfilePath))
    {
        return $false
    }
    
    $headerIndex = 0
    $found = $false
    $scriptCall = $null
    
    Get-Content -Path $systemProfilePath | ForEach-Object -Process {
        $headerIndex++
        if ($found)
        {
            $scriptCall = $_
            return
        }
        if ($_ -match [regex]::Escape($ExpectedScriptHeader))
        {
            $found = $true
        }
    }

    if (-not $scriptCall)
    {
        return $false
    }

    return $scriptCall -eq $ExpectedScriptCall
}

function Remove-Diacritics {
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$Text
    )
    process
    {
        $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object Text.StringBuilder

        $normalized.ToCharArray() | ForEach-Object {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark)
            {
                [void]$sb.Append($_)
            }
        }

        return $sb.ToString()
    }
}

# Main execution - Lecture depuis stdin
try {
    $jsonInput = [Console]::In.ReadToEnd()
    $inputObject = $jsonInput | ConvertFrom-Json

    $result = switch ($Operation) {
        'Get' { Get-PSProfileState -InputObject $inputObject }
        'Test' { [PSCustomObject]@{ InDesiredState = Test-PSProfileState -InputObject $inputObject } }
        'Set' { Set-PSProfileState -InputObject $inputObject }
    }

    # Sortie JSON avec profondeur suffisante
    Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}