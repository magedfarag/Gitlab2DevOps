# Test Wiki API
Import-Module .\modules\AzureDevOps\Wikis.psm1 -Force
Import-Module .\modules\core\Core.Rest.psm1 -Force

# Test minimal wiki page creation
$testContent = "# Test Page`n`nThis is a test wiki page."
try {
    Set-AdoWikiPage -Project "edamah" -WikiId "e01b7cc9-aca3-4ef6-83e9-721b623ba1fb" -Path "/TestPage" -Markdown $testContent
    Write-Host "SUCCESS: Test wiki page created"
} catch {
    Write-Host "FAILED: $_"
}