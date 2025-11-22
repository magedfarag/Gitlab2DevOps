# Test Emoji Content
Import-Module .\modules\AzureDevOps\Wikis.psm1 -Force
Import-Module .\modules\core\Core.Rest.psm1 -Force

# Test with emojis that were in the failing content
$testContent = @"
# Test with Emojis

### Key Results (OKRs)
| Objective | Key Result | Target | Current | Status |
|-----------|------------|--------|---------|--------|
| Delivery reliability | Reduce lead time for changes | 50% reduction vs. baseline | 20% | 🟡 On Track |
| Product quality | Keep P1 production bugs | < 5 per sprint | 8 | 🔴 At Risk |
| Team health | Maintain team satisfaction score | > 8.0 / 10 | 7.5 | 🟡 On Track |

### Status Indicators
- 🟢 Green: On track
- 🟡 Yellow: At risk
- 🔴 Red: Off track
"@

try {
    Set-AdoWikiPage -Project "edamah" -WikiId "e01b7cc9-aca3-4ef6-83e9-721b623ba1fb" -Path "/TestEmojiContent" -Markdown $testContent
    Write-Host "SUCCESS: Emoji content test passed"
} catch {
    Write-Host "FAILED: $_"
}