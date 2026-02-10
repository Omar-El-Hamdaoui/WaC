#.\Publish-MyModule.ps1 -VersionBump Patch -ReleaseNotes "This is a test Note"
.\Publish-MyModule.ps1
cd ..
.\install-MyDscResources.ps1 -Force