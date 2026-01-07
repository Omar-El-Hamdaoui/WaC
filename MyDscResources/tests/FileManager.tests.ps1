# FileManager.tests.ps1
# Tests Pester pour valider la ressource DSC FileManager

BeforeAll {
    # ✅ Pointer vers le sous-dossier FileManager DIRECTEMENT
    $resourcePath = Join-Path $PSScriptRoot "..\resources\FileManager"
    $resourcePath = Resolve-Path $resourcePath
    
    # Nettoyer et ajouter au PATH
    $env:PATH = $env:PATH -replace [regex]::Escape($resourcePath), ''
    $env:PATH = "$resourcePath;$env:PATH"
    
    Write-Host "`n=== FileManager Resource Tests ===" -ForegroundColor Cyan
    Write-Host "Resource path: $resourcePath" -ForegroundColor Yellow
    
    # Vérifier que les fichiers existent
    $manifestPath = Join-Path $resourcePath "FileManager.dsc.resource.json"
    $scriptPath = Join-Path $resourcePath "FileManager.ps1"
    
    if (-not (Test-Path $manifestPath)) {
        throw "❌ Manifest not found: $manifestPath"
    }
    
    if (-not (Test-Path $scriptPath)) {
        throw "❌ Script not found: $scriptPath"
    }
    
    Write-Host "✓ Manifest found" -ForegroundColor Green
    Write-Host "✓ Script found" -ForegroundColor Green
    
    # Vérifier la découverte DSC
    $discovered = dsc resource list 2>$null | Select-String "MyCompany.Storage/FileManager"
    if (-not $discovered) {
        Write-Host "❌ FileManager NOT discovered by DSC!" -ForegroundColor Red
        throw "Resource discovery failed"
    }
    
    Write-Host "✓ FileManager discovered by DSC" -ForegroundColor Green
    
    # Créer un répertoire temporaire pour les tests
    $script:testBasePath = Join-Path $env:TEMP "DscTests_$(Get-Random)"
    New-Item -Path $script:testBasePath -ItemType Directory -Force | Out-Null
    
    Write-Host "Tests running in: $script:testBasePath`n" -ForegroundColor Cyan
}

Describe 'MyCompany.Storage/FileManager Resource' {
    
    Context 'Get Operation' {
        
        It 'Returns correct state for existing file' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "test.txt"
            "Test Content" | Set-Content -Path $testFile -NoNewline
            
            # Act
            $jsonInput = @{
                path = $testFile
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Storage/FileManager --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState.ensure | Should -Be 'Present'
            $result.actualState.content | Should -Be 'Test Content'
        }
        
        It 'Returns Absent for non-existent file' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "missing.txt"
            
            # Act
            $jsonInput = @{
                path = $testFile
            } | ConvertTo-Json -Compress
            
            $output = dsc resource get --resource MyCompany.Storage/FileManager --input $jsonInput
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
            
            $jsonInput = @{
                path = $testFile
                content = "Desired Content"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Storage/FileManager --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState._inDesiredState | Should -Be $true
        }
        
        It 'Returns false when not in desired state' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "new.txt"
            
            $jsonInput = @{
                path = $testFile
                content = "New Content"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            $output = dsc resource test --resource MyCompany.Storage/FileManager --input $jsonInput
            $result = $output | ConvertFrom-Json
            
            # Assert
            $result.actualState._inDesiredState | Should -Be $false
        }
    }
    
    Context 'Set Operation' {
        
        It 'Creates file with content' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "created.txt"
            
            $jsonInput = @{
                path = $testFile
                content = "Created by DSC"
                ensure = "Present"
            } | ConvertTo-Json -Compress
            
            # Act
            dsc resource set --resource MyCompany.Storage/FileManager --input $jsonInput | Out-Null
            
            # Assert
            Test-Path -Path $testFile | Should -Be $true
            $actualContent = (Get-Content -Path $testFile -Raw).TrimEnd("`r`n")
            $actualContent | Should -Be "Created by DSC"
        }
        
        It 'Removes file when Ensure is Absent' {
            # Arrange
            $testFile = Join-Path $script:testBasePath "remove.txt"
            "To be removed" | Set-Content -Path $testFile
            
            $jsonInput = @{
                path = $testFile
                ensure = "Absent"
            } | ConvertTo-Json -Compress
            
            # Act
            dsc resource set --resource MyCompany.Storage/FileManager --input $jsonInput | Out-Null
            
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