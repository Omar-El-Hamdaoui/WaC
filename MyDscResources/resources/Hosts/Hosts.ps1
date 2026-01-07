[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Get', 'Set', 'Test')]
    [string]$Operation
)

function Get-HostsState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $name = $InputObject.Name
    $path = $InputObject.Path
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $etcDirectory = [System.Environment]::GetEnvironmentVariable('SystemRoot') + '\System32\drivers\etc'
    $hostsFilePath = Get-HostsFilePath -Name $name -EtcDirectory $etcDirectory
    
    $currentEnsure = 'Absent'
    
    if ((Test-MatchingHash -SourceFile $hostsFilePath -TargetFile $path) -and
        (Test-ContentInHostsFile -HostsFilePath $hostsFilePath -EtcDirectory $etcDirectory))
    {
        $currentEnsure = 'Present'
    }

    return [PSCustomObject]@{
        Name = $name
        Path = $path
        Ensure = $currentEnsure
    }
}

function Test-HostsState {
    param($InputObject)
    
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    $current = Get-HostsState -InputObject $InputObject
    
    return $current.Ensure -eq $ensure
}

function Set-HostsState {
    param($InputObject)
    
    # Extraire les valeurs avec des défauts
    $name = $InputObject.Name
    $path = $InputObject.Path
    $ensure = if ($InputObject.Ensure) { $InputObject.Ensure } else { 'Present' }
    
    $etcDirectory = [System.Environment]::GetEnvironmentVariable('SystemRoot') + '\System32\drivers\etc'
    $hostsFilePath = Get-HostsFilePath -Name $name -EtcDirectory $etcDirectory
    
    if ($ensure -eq 'Present')
    {
        # Copy the source hosts file if it's different from the current one.
        if (-not (Test-MatchingHash -SourceFile $hostsFilePath -TargetFile $path))
        {
            Copy-Item -Path $path -Destination $hostsFilePath -Force
        }
    }
    elseif ($ensure -eq 'Absent')
    {
        if (Test-Path -Path $hostsFilePath)
        {
            Remove-Item -Path $hostsFilePath -Force
        }
    }
    
    # Merge all hosts files into the system hosts file
    Merge-HostsFiles -EtcDirectory $etcDirectory
    
    return Get-HostsState -InputObject $InputObject
}

function Get-HostsFilePath {
    param(
        [string]$Name,
        [string]$EtcDirectory
    )
    
    $fileName = $Name -replace '\s', '' | Remove-Diacritics
    return Join-Path -Path $EtcDirectory -ChildPath "$fileName.hosts"
}

function Test-MatchingHash {
    param(
        [string]$SourceFile,
        [string]$TargetFile
    )
    
    if (-not (Test-Path -Path $SourceFile) -or
        -not (Test-Path -Path $TargetFile))
    {
        return $false
    }

    $sourceFileHash = (Get-FileHash -Path $SourceFile).Hash
    $targetFileHash = (Get-FileHash -Path $TargetFile).Hash

    return $sourceFileHash -eq $targetFileHash
}

function Test-ContentInHostsFile {
    param(
        [string]$HostsFilePath,
        [string]$EtcDirectory
    )
    
    if (-not (Test-Path -Path $HostsFilePath))
    {
        return $false
    }
    
    $systemHostsPath = Join-Path -Path $EtcDirectory -ChildPath 'hosts'
    
    if (-not (Test-Path -Path $systemHostsPath))
    {
        return $false
    }
    
    $systemHostsContent = Get-Content -Path $systemHostsPath -Raw
    $hostsFileContent = Get-Content -Path $HostsFilePath -Raw
    $hostsFileContent = $hostsFileContent -replace '^\s*\r\n|\r\n\s*$'

    return $systemHostsContent.Contains($hostsFileContent)
}

function Merge-HostsFiles {
    param(
        [string]$EtcDirectory
    )
    
    $systemHosts = Join-Path -Path $EtcDirectory -ChildPath 'hosts'
    $defaultBackupPath = Join-Path -Path $EtcDirectory -ChildPath 'default.hosts'

    # Ensure default backup exists
    if (-not (Test-Path -Path $defaultBackupPath))
    {
        Copy-Item -Path $systemHosts -Destination $defaultBackupPath
    }

    # Start with the content of default.hosts file
    $allHostsContent = Get-Content -Path $defaultBackupPath -Raw
    $allHostsContent = $allHostsContent -replace '^\s*\r\n|\r\n\s*$'
    $allHostsContent += "`n"

    # Concatenate all other *.hosts files, with headers
    $allHostsFiles = Get-ChildItem -Path $EtcDirectory -Filter '*.hosts' | Where-Object { $_.Name -ne 'default.hosts' }

    foreach ($file in $allHostsFiles)
    {
        $fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $header = '##################################################' + "`n" +
        "# $fileNameWithoutExtension" + "`n" +
        '##################################################' + "`n`n"

        $fileContent = Get-Content -Path $file.FullName -Raw
        $fileContent = $fileContent -replace '^\s*\r\n|\r\n\s*$'

        # Append the header and content
        $allHostsContent += "`n" + $header + $fileContent
    }

    # Write the concatenated content to the system hosts file
    Set-Content -Path $systemHosts -Value $allHostsContent
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
        'Get' { Get-HostsState -InputObject $inputObject }
        'Test' { 
            $testResult = Test-HostsState -InputObject $inputObject
            # Pour l'opération Test, on doit retourner l'état actuel avec la propriété InDesiredState
            $currentState = Get-HostsState -InputObject $inputObject
            $currentState | Add-Member -MemberType NoteProperty -Name 'InDesiredState' -Value $testResult -Force
            $currentState
        }
        'Set' { Set-HostsState -InputObject $inputObject }
    }

    # Sortie JSON avec profondeur suffisante
    Write-Output ($result | ConvertTo-Json -Depth 10 -Compress)
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}