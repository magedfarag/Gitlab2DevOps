# Create sample Excel requirements file
Import-Module ImportExcel -ErrorAction Stop

Write-Host "[INFO] Creating sample requirements Excel file..." -ForegroundColor Cyan


# Build full hierarchy: 1 Epic, 3 Features, 10 of each type under each Feature
$data = @()
$localId = 1

# Epic
$data += [PSCustomObject]@{
    LocalId = $localId
    ParentLocalId = $null
    WorkItemType = 'Epic'
    Title = 'E-Commerce Platform'
    Description = 'Complete online shopping platform with payment integration and customer management'
    AreaPath = ''
    IterationPath = ''
    State = 'New'
    Priority = 1
    StoryPoints = $null
    BusinessValue = 10000
    ValueArea = 'Business'
    Risk = '2 - Medium'
    StartDate = '2025-11-15'
    FinishDate = '2026-03-31'
    TargetDate = '2026-03-31'
    DueDate = $null
    OriginalEstimate = $null
    RemainingWork = $null
    CompletedWork = $null
    TestSteps = $null
    Tags = 'strategic;revenue;q1-2026'
}
$epicId = $localId
$localId++

# 3 Features
for ($f=1; $f -le 2; $f++) {
    $data += [PSCustomObject]@{
        LocalId = $localId
        ParentLocalId = $epicId
        WorkItemType = 'Feature'
        Title = "Feature $f : Shopping Cart System"
        Description = "Feature $f : Implement shopping cart functionality including add to cart, update quantities, remove items, and checkout flow"
        AreaPath = ''
        IterationPath = ''
        State = 'New'
        Priority = 1
        StoryPoints = $null
        BusinessValue = 5000
        ValueArea = 'Business'
        Risk = '3 - Low'
        StartDate = '2025-11-15'
        FinishDate = '2025-12-31'
        TargetDate = '2025-12-31'
        DueDate = $null
        OriginalEstimate = $null
        RemainingWork = $null
        CompletedWork = $null
        TestSteps = $null
        Tags = "cart;ecommerce;sprint$f"
    }
    $featureId = $localId
    $localId++

    # 10 User Stories under each Feature
    for ($us=1; $us -le 3; $us++) {
        $data += [PSCustomObject]@{
            LocalId = $localId
            ParentLocalId = $featureId
            WorkItemType = 'User Story'
            Title = "Feature $f - User Story $us : Add Product to Cart"
            Description = "As a customer, I want to add products to my cart so I can purchase multiple items in one transaction. (Feature $f, Story $us)"
            AreaPath = ''
            IterationPath = ''
            State = 'Active'
            Priority = 1
            StoryPoints = 5
            BusinessValue = $null
            ValueArea = 'Business'
            Risk = $null
            StartDate = '2025-11-20'
            FinishDate = '2025-11-27'
            TargetDate = $null
            DueDate = $null
            OriginalEstimate = 16
            RemainingWork = 12
            CompletedWork = 4
            TestSteps = $null
            Tags = "frontend;cart;in-progress;feature$f;story$us"
        }
        $userStoryId = $localId
        $localId++

        # 10 Tasks under each User Story
        for ($t=1; $t -le 2; $t++) {
            $data += [PSCustomObject]@{
                LocalId = $localId
                ParentLocalId = $userStoryId
                WorkItemType = 'Task'
                Title = "Feature $f - Story $us - Task $t : Create Add to Cart API Endpoint"
                Description = "Implement POST /api/cart/items endpoint with request validation, authentication, and error handling (Feature $f, Story $us, Task $t)"
                AreaPath = ''
                IterationPath = ''
                State = 'Active'
                Priority = 1
                StoryPoints = $null
                BusinessValue = $null
                ValueArea = $null
                Risk = $null
                StartDate = '2025-11-20'
                FinishDate = '2025-11-22'
                TargetDate = $null
                DueDate = $null
                OriginalEstimate = 8
                RemainingWork = 6
                CompletedWork = 2
                TestSteps = $null
                Tags = "backend;api;development;feature$f;story$us;task$t"
            }
            $taskId = $localId
            $localId++
        }

        # 10 Bugs under each User Story
        for ($b=1; $b -le 2; $b++) {
            $data += [PSCustomObject]@{
                LocalId = $localId
                ParentLocalId = $userStoryId
                WorkItemType = 'Bug'
                Title = "Feature $f - Story $us - Bug $b : Cart quantity not updating on rapid clicks"
                Description = "Steps to Reproduce: Rapidly click Add to Cart. Expected: Quantity increases by 1 per click. Actual: Quantity increases by 2 or more. (Feature $f, Story $us, Bug $b)"
                AreaPath = ''
                IterationPath = ''
                State = 'New'
                Priority = 2
                StoryPoints = $null
                BusinessValue = $null
                ValueArea = $null
                Risk = $null
                StartDate = $null
                FinishDate = $null
                TargetDate = $null
                DueDate = '2025-11-25'
                OriginalEstimate = 4
                RemainingWork = 4
                CompletedWork = 0
                TestSteps = $null
                Tags = "frontend;bug;cart;high-priority;feature$f;story$us;bug$b"
            }
            $bugId = $localId
            $localId++
        }

        # 10 Test Cases under each User Story
        for ($tc=1; $tc -le 2; $tc++) {
            $data += [PSCustomObject]@{
                LocalId = $localId
                ParentLocalId = $userStoryId
                WorkItemType = 'Test Case'
                Title = "Feature $f - Story $us - Test Case $tc : Verify Add to Cart Success Flow"
                Description = "Verify that users can successfully add products to their shopping cart and see correct confirmation (Feature $f, Story $us, TestCase $tc)"
                AreaPath = ''
                IterationPath = ''
                State = 'New'
                Priority = 1
                StoryPoints = $null
                BusinessValue = $null
                ValueArea = $null
                Risk = $null
                StartDate = $null
                FinishDate = $null
                TargetDate = $null
                DueDate = $null
                OriginalEstimate = $null
                RemainingWork = $null
                CompletedWork = $null
                TestSteps = "Navigate to product page|Product details page loads with Add to Cart button visible;;Click Add to Cart button|Success message appears: Product added to cart;;Verify cart badge|Cart count badge increments by 1;;Open shopping cart|Cart page displays with added product;;Verify product details|Product name, price, quantity (1), and image match original product"
                Tags = "testing;cart;smoke;regression;feature$f;story$us;testcase$tc"
            }
            $testCaseId = $localId
            $localId++
        }
    }
}

$excelPath = Join-Path $PSScriptRoot "migrations\demo\requirements.xlsx"

# Create Excel file
$data | Export-Excel -Path $excelPath `
                     -WorksheetName 'Requirements' `
                     -AutoSize `
                     -BoldTopRow `
                     -FreezeTopRow `
                     -TableName 'RequirementsTable'

Write-Host ""
Write-Host "[SUCCESS] Created sample Excel file: $excelPath" -ForegroundColor Green
Write-Host ""
Write-Host "Work Items Created:" -ForegroundColor Cyan
Write-Host "  1 Epic         - E-Commerce Platform" -ForegroundColor White
Write-Host "  1 Feature      - Shopping Cart System (child of Epic)" -ForegroundColor White
Write-Host "  1 User Story   - Add Product to Cart (child of Feature)" -ForegroundColor White
Write-Host "  1 Task         - Create Add to Cart API Endpoint (child of User Story)" -ForegroundColor White
Write-Host "  1 Bug          - Cart quantity issue (child of User Story)" -ForegroundColor White
Write-Host "  1 Test Case    - Verify Add to Cart (child of User Story)" -ForegroundColor White
Write-Host ""
Write-Host "Hierarchy:" -ForegroundColor Cyan
Write-Host "  Epic (1)" -ForegroundColor Gray
Write-Host "  └── Feature (2)" -ForegroundColor Gray
Write-Host "      └── User Story (3)" -ForegroundColor Gray
Write-Host "         ├── Task (4)" -ForegroundColor Gray
Write-Host "         ├── Bug (5)" -ForegroundColor Gray
Write-Host "         └── Test Case (6)" -ForegroundColor Gray
Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  Import-AdoWorkItemsFromExcel -Project 'demo' -ExcelPath '$excelPath'" -ForegroundColor Yellow
