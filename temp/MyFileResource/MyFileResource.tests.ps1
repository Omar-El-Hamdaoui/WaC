# MyFileResource.tests.ps1
# Tests Pester pour valider la ressource DSC FileManager

BeforeAll {
    # Configuration initiale avant tous les tests
    $resourcePath = $PSScriptRoot
    $env:PATH = "$resourcePath;$env:PATH"
    
    # Utiliser un chemin temporaire réel au lieu de TestDrive:
    # TestDrive: ne fonctionne pas avec les commandes DSC externes
    $script:testBasePath = Join-Path $env:TEMP "DscTests_$(Get-Random)"
    New-Item -Path $script:testBasePath -ItemType Directory -Force | Out-Null
    
    Write-Host "Tests running in: $script:testBasePath" -ForegroundColor Cyan
}

Describe 'MyCompany.Storage/FileManager Resource' {
    
    Context 'Get Operation' {
        
        It 'Returns correct state for existing file' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "test.txt"
            "Test Content" | Set-Content -Path $testFile -NoNewline
            
            # Act
            $input = @{
                path = $testFile
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Storage/FileManager --input $input
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState.ensure | Should -Be 'Present'
            $result.actualState.content | Should -Be 'Test Content'
        }
        
        It 'Returns Absent for non-existent file' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "missing.txt"
            
            # Act
            $input = @{
                path = $testFile
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Storage/FileManager --input $input
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState.ensure | Should -Be 'Absent'
            $result.actualState.content | Should -Be $null
        }
    }
    
    Context 'Test Operation' {
        
        It 'Returns true when in desired state' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "desired.txt"
            "Desired Content" | Set-Content -Path $testFile -NoNewline
            
            $input = @{
                path = $testFile
                content = "Desired Content"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Storage/FileManager --input $input
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState._inDesiredState | Should -Be $true
        }
        
        It 'Returns false when not in desired state' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "new.txt"
            
            $input = @{
                path = $testFile
                content = "New Content"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Storage/FileManager --input $input
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState._inDesiredState | Should -Be $false
        }
    }
    
    Context 'Set Operation' {
        
        It 'Creates file with content' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "created.txt"
            
            $input = @{
                path = $testFile
                content = "Created by DSC"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            dsc resource set --resource MyCompany.Storage/FileManager --input $input | Out-Null
            
            # Assert
            Test-Path -Path $testFile | Should -Be $true
            $actualContent = (Get-Content -Path $testFile -Raw).TrimEnd("`r`n")
            $actualContent | Should -Be "Created by DSC"
        }
        
        It 'Removes file when Ensure is Absent' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "remove.txt"
            "To be removed" | Set-Content -Path $testFile
            
            $input = @{
                path = $testFile
                ensure = "Absent"
            } | ConvertTo-Json -Compress
            
            # Act
            dsc resource set --resource MyCompany.Storage/FileManager --input $input | Out-Null
            
            # Assert
            Test-Path -Path $testFile | Should -Be $false
        }
    }
}

AfterAll {
    # Nettoyage
    if (Test-Path $script:testBasePath) {
        Remove-Item -Path $script:testBasePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned up test directory: $script:testBasePath" -ForegroundColor Green
    }
}