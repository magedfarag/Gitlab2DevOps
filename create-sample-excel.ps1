# Create sample Excel requirements file
Import-Module ImportExcel -ErrorAction Stop

Write-Host "[INFO] Creating sample requirements Excel file..." -ForegroundColor Cyan

$data = @(
    # Epic
    [PSCustomObject]@{
        LocalId = 1
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
    
    # Feature
    [PSCustomObject]@{
        LocalId = 2
        ParentLocalId = 1
        WorkItemType = 'Feature'
        Title = 'Shopping Cart System'
        Description = 'Implement shopping cart functionality including add to cart, update quantities, remove items, and checkout flow'
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
        Tags = 'cart;ecommerce;sprint1'
    }
    
    # User Story
    [PSCustomObject]@{
        LocalId = 3
        ParentLocalId = 2
        WorkItemType = 'User Story'
        Title = 'Add Product to Cart'
        Description = '<p>As a <strong>customer</strong>, I want to add products to my cart so I can purchase multiple items in one transaction.</p><p><strong>Acceptance Criteria:</strong></p><ul><li>Add to Cart button visible on product page</li><li>Success message shown after adding</li><li>Cart count badge updates</li><li>Product appears in cart with correct details</li></ul>'
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
        Tags = 'frontend;cart;in-progress'
    }
    
    # Task
    [PSCustomObject]@{
        LocalId = 4
        ParentLocalId = 3
        WorkItemType = 'Task'
        Title = 'Create Add to Cart API Endpoint'
        Description = 'Implement POST /api/cart/items endpoint with request validation, authentication, and error handling'
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
        Tags = 'backend;api;development'
    }
    
    # Bug
    [PSCustomObject]@{
        LocalId = 5
        ParentLocalId = 3
        WorkItemType = 'Bug'
        Title = 'Cart quantity not updating on rapid clicks'
        Description = '<p><strong>Steps to Reproduce:</strong></p><ol><li>Navigate to any product page</li><li>Double-click or rapidly click "Add to Cart" button</li><li>Open shopping cart</li></ol><p><strong>Expected:</strong> Quantity increases by 1 per click<br><strong>Actual:</strong> Quantity increases by 2 or more, causing incorrect totals</p><p><strong>Environment:</strong> Chrome 120, Firefox 121</p>'
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
        Tags = 'frontend;bug;cart;high-priority'
    }
    
    # Test Case
    [PSCustomObject]@{
        LocalId = 6
        ParentLocalId = 3
        WorkItemType = 'Test Case'
        Title = 'Verify Add to Cart Success Flow'
        Description = 'Verify that users can successfully add products to their shopping cart and see correct confirmation'
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
        TestSteps = 'Navigate to product page|Product details page loads with Add to Cart button visible;;Click Add to Cart button|Success message appears: Product added to cart;;Verify cart badge|Cart count badge increments by 1;;Open shopping cart|Cart page displays with added product;;Verify product details|Product name, price, quantity (1), and image match original product'
        Tags = 'testing;cart;smoke;regression'
    }
    
    # Issue
    [PSCustomObject]@{
        LocalId = 7
        ParentLocalId = 2
        WorkItemType = 'Issue'
        Title = 'Payment gateway integration documentation missing'
        Description = 'Development team needs comprehensive documentation for payment gateway integration including API keys setup, webhook configuration, and error handling patterns'
        AreaPath = ''
        IterationPath = ''
        State = 'New'
        Priority = 3
        StoryPoints = $null
        BusinessValue = $null
        ValueArea = $null
        Risk = $null
        StartDate = $null
        FinishDate = $null
        TargetDate = $null
        DueDate = '2025-12-01'
        OriginalEstimate = $null
        RemainingWork = $null
        CompletedWork = $null
        TestSteps = $null
        Tags = 'documentation;payment;technical-debt'
    }
)

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
Write-Host "  1 Issue        - Documentation gap (child of Feature)" -ForegroundColor White
Write-Host ""
Write-Host "Hierarchy:" -ForegroundColor Cyan
Write-Host "  Epic (1)" -ForegroundColor Gray
Write-Host "  └── Feature (2)" -ForegroundColor Gray
Write-Host "      ├── User Story (3)" -ForegroundColor Gray
Write-Host "      │   ├── Task (4)" -ForegroundColor Gray
Write-Host "      │   ├── Bug (5)" -ForegroundColor Gray
Write-Host "      │   └── Test Case (6)" -ForegroundColor Gray
Write-Host "      └── Issue (7)" -ForegroundColor Gray
Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  Import-AdoWorkItemsFromExcel -Project 'demo' -ExcelPath '$excelPath'" -ForegroundColor Yellow
