<#
.SYNOPSIS
    Repository management and branch policies

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest

#>
function Ensure-AdoRepositoryTemplates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$RepoName
    )
    
    Write-Host "[INFO] Adding repository template files..." -ForegroundColor Cyan
    
    # Check if repository has any commits (needed to add files)
    $hasCommits = $false
    try {
        $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/commits?``$top=1"
        $hasCommits = $commits.count -gt 0
    }
    catch {
        Write-Verbose "[Ensure-AdoRepositoryTemplates] Could not check commits: $_"
    }
    
    if (-not $hasCommits) {
        Write-Host "[INFO] Repository is empty - templates will be added on first push" -ForegroundColor Yellow
        Write-Host "[INFO] Skipping template files (repository needs at least one commit)" -ForegroundColor Yellow
        return @()
    }
    
    # Get default branch
    $defaultBranch = Get-AdoRepoDefaultBranch $Project $RepoId
    if (-not $defaultBranch) {
        Write-Host "[INFO] No default branch found - skipping template files" -ForegroundColor Yellow
        return @()
    }
    
    # Extract branch name from refs/heads/main
    $branchName = $defaultBranch -replace '^refs/heads/', ''
    
    # Define template files
    $readmeContent = @"
# $RepoName

## Overview
Brief description of the project and its purpose.

## Getting Started

### Prerequisites
- List any prerequisites here
- Development tools required
- Dependencies needed

### Installation
````````````bash
# Clone the repository
git clone <repository-url>

# Install dependencies
# Add installation commands here
````````````

### Running Locally
````````````bash
# Add commands to run the application locally
````````````

## Development Workflow

1. Create a feature branch from \``main\``
   ````````````bash
   git checkout -b feature/your-feature-name
   ````````````

2. Make your changes and commit
   ````````````bash
   git add .
   git commit -m "Description of changes"
   ````````````

3. Push and create a pull request
   ````````````bash
   git push origin feature/your-feature-name
   ````````````

4. Link your work items in the PR description
5. Request code review
6. Merge after approval

## Project Structure
````````````
/src        - Source code
/docs       - Documentation
/tests      - Test files
/scripts    - Build and deployment scripts
````````````

## Contributing
- Follow the team's coding standards
- Write tests for new features
- Update documentation as needed
- Link work items to pull requests

## Support
For questions or issues, contact the team or create a work item.
"@

    $prTemplateContent = @"
## Description
<!-- Provide a brief description of the changes in this PR -->

## Related Work Items
<!-- Link work items using #<work-item-id> -->
- Fixes #
- Related to #

## Type of Change
<!-- Check the relevant options -->
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Refactoring (no functional changes)

## Testing Done
<!-- Describe the testing you've performed -->
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Manual testing completed
- [ ] All tests passing

## Checklist
- [ ] Code follows team coding standards
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated (if needed)
- [ ] No new warnings generated
- [ ] Work items linked above

## Screenshots (if applicable)
<!-- Add screenshots for UI changes -->

## Additional Notes
<!-- Any additional information reviewers should know -->
"@

    $filesCreated = @()
    $createdCount = 0
    $skippedCount = 0
    
    # Check and create README.md
    try {
        $existingReadme = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/README.md"
        if ($existingReadme) {
            Write-Host "[INFO] README.md already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-Verbose "[Ensure-AdoRepositoryTemplates] Creating README.md"
            $pushBody = @{
                refUpdates = @(
                    @{
                        name = $defaultBranch
                        oldObjectId = (Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$branchName").value[0].objectId
                    }
                )
                commits = @(
                    @{
                        comment = "Add README.md template"
                        changes = @(
                            @{
                                changeType = "add"
                                item = @{ path = "/README.md" }
                                newContent = @{
                                    content = $readmeContent
                                    contentType = "rawtext"
                                }
                            }
                        )
                    }
                )
            }
            
            $result = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushBody
            Write-Host "[SUCCESS] Created README.md" -ForegroundColor Green
            $filesCreated += "README.md"
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create README.md: $_"
        }
    }
    
    # Check and create PR template
    try {
        $existingPR = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.azuredevops/pull_request_template.md"
        if ($existingPR) {
            Write-Host "[INFO] PR template already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-Verbose "[Ensure-AdoRepositoryTemplates] Creating .azuredevops/pull_request_template.md"
            $pushBody = @{
                refUpdates = @(
                    @{
                        name = $defaultBranch
                        oldObjectId = (Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$branchName").value[0].objectId
                    }
                )
                commits = @(
                    @{
                        comment = "Add pull request template"
                        changes = @(
                            @{
                                changeType = "add"
                                item = @{ path = "/.azuredevops/pull_request_template.md" }
                                newContent = @{
                                    content = $prTemplateContent
                                    contentType = "rawtext"
                                }
                            }
                        )
                    }
                )
            }
            
            $result = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushBody
            Write-Host "[SUCCESS] Created .azuredevops/pull_request_template.md" -ForegroundColor Green
            $filesCreated += ".azuredevops/pull_request_template.md"
            $createdCount++
        }
        catch {
            Write-Warning "Failed to create PR template: $_"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "[INFO] Repository templates summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Created: $createdCount files" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "  ⏭️ Skipped: $skippedCount files (already exist)" -ForegroundColor Yellow
    }
    
    return $filesCreated
}

#>
function Ensure-AdoRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$ProjId,
        
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [switch]$AllowExisting,
        
        [switch]$Replace
    )
    
    Write-Verbose "[Ensure-AdoRepository] Checking if repository '$RepoName' exists..."
    
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories"
    $existing = $repos.value | Where-Object { $_.name -eq $RepoName }
    
    if ($existing) {
        Write-Verbose "[Ensure-AdoRepository] Repository '$RepoName' exists (ID: $($existing.id))"
        
        # Check if repository has commits
        try {
            $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)/commits?``$top=1"
            $hasCommits = $commits.count -gt 0
        }
        catch {
            $hasCommits = $false
        }
        
        if ($hasCommits) {
            Write-Verbose "[Ensure-AdoRepository] Repository has $($commits.count) commit(s)"
            
            if ($Replace) {
                if ($PSCmdlet.ShouldProcess($RepoName, "DELETE and recreate repository (has existing commits)")) {
                    Write-Warning "Repository '$RepoName' has commits. Deleting and recreating due to -Replace flag..."
                    
                    # Delete existing repository
                    Invoke-AdoRest DELETE "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)"
                    Start-Sleep -Seconds 2
                    
                    # Create new repository
                    Write-Host "[INFO] Creating new repository: $RepoName" -ForegroundColor Cyan
                    return Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{
                        name    = $RepoName
                        project = @{ id = $ProjId }
                    }
                }
            }
            else {
                $msg = "Repository '$RepoName' already exists with $($commits.count) commit(s). "
                $msg += "Use -Replace to delete and recreate, or -AllowExisting to sync content."
                throw $msg
            }
        }
        
        if ($AllowExisting) {
            Write-Host "[INFO] Repository '$RepoName' already exists. Will sync/update content." -ForegroundColor Green
            return $existing
        }
        else {
            Write-Host "[INFO] Repository '$RepoName' already exists (empty) - no changes needed" -ForegroundColor Green
            return $existing
        }
    }
    
    # Repository does not exist - create it
    if ($PSCmdlet.ShouldProcess($RepoName, "Create new repository")) {
        Write-Host "[INFO] Creating new repository: $RepoName" -ForegroundColor Cyan
        $newRepo = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{
            name    = $RepoName
            project = @{ id = $ProjId }
        }
        Write-Host "[SUCCESS] Repository '$RepoName' created successfully" -ForegroundColor Green
        return $newRepo
    }
    else {
        Write-Warning "Repository creation was cancelled by the user"
        return $null
    }
}

#>
function Get-AdoRepoDefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId
    )
    
    try {
        $r = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
        if ($r.PSObject.Properties['defaultBranch'] -and $r.defaultBranch) {
            Write-Verbose "[Get-AdoRepoDefaultBranch] Found default branch: $($r.defaultBranch)"
            return $r.defaultBranch
        }
        else {
            Write-Warning "Repository has no default branch yet (empty repository). Branch policies will be skipped."
            return $null
        }
    }
    catch {
        Write-Warning "Failed to get default branch: $_"
        return $null
    }
}

#>
function Ensure-AdoBranchPolicies {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$Ref,
        
        [int]$Min = 2,
        
        [int]$BuildId = 0,
        
        [string]$StatusContext = ""
    )
    
    Write-Verbose "[Ensure-AdoBranchPolicies] Checking existing policies for ref '$Ref'..."
    
    $cfgs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations"
    $scope = @{ repositoryId = $RepoId; refName = $Ref; matchKind = "exact" }
    
    function Test-PolicyExists([string]$id) {
        $cfgs.value | Where-Object { $_.type.id -eq $id -and $_.settings.scope[0].refName -eq $Ref }
    }
    
    # Required reviewers policy
    $existing = Test-PolicyExists $script:POLICY_REQUIRED_REVIEWERS
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create required reviewers policy (min: $Min)")) {
            Write-Host "[INFO] Creating required reviewers policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_REQUIRED_REVIEWERS }
                settings   = @{
                    minimumApproverCount = [Math]::Max(1, $Min)
                    creatorVoteCounts    = $false
                    allowDownvotes       = $true
                    resetOnSourcePush    = $false
                    scope                = @($scope)
                }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Required reviewers policy already exists"
    }
    
    # Work item link policy
    $existing = Test-PolicyExists $script:POLICY_WORK_ITEM_LINK
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create work item link policy")) {
            Write-Host "[INFO] Creating work item link policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_WORK_ITEM_LINK }
                settings   = @{ scope = @($scope) }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Work item link policy already exists"
    }
    
    # Comment resolution policy
    $existing = Test-PolicyExists $script:POLICY_COMMENT_RESOLUTION
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($Ref, "Create comment resolution policy")) {
            Write-Host "[INFO] Creating comment resolution policy" -ForegroundColor Cyan
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                isEnabled  = $true
                isBlocking = $true
                type       = @{ id = $script:POLICY_COMMENT_RESOLUTION }
                settings   = @{ scope = @($scope) }
            } | Out-Null
        }
    }
    else {
        Write-Verbose "[Ensure-AdoBranchPolicies] Comment resolution policy already exists"
    }
    
    # Build validation policy
    if ($BuildId -gt 0) {
        $existing = Test-PolicyExists $script:POLICY_BUILD_VALIDATION
        if (-not $existing) {
            if ($PSCmdlet.ShouldProcess($Ref, "Create build validation policy (Build ID: $BuildId)")) {
                Write-Host "[INFO] Creating build validation policy" -ForegroundColor Cyan
                Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
                    isEnabled  = $true
                    isBlocking = $true
                    type       = @{ id = $script:POLICY_BUILD_VALIDATION }
                    settings   = @{
                        displayName             = "CI validation"
                        validDuration           = 0
                        queueOnSourceUpdateOnly = $false
                        buildDefinitionId       = $BuildId
                        scope                   = @($scope)
                    }
                } | Out-Null
            }
        }
        else {
            Write-Verbose "[Ensure-AdoBranchPolicies] Build validation policy already exists"
        }
    }
    
    # Status check policy
    if ($StatusContext -and -not (Test-PolicyExists $script:POLICY_STATUS_CHECK)) {
        Write-Host "[INFO] Creating status check policy"
        Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations" -Body @{
            isEnabled  = $true
            isBlocking = $true
            type       = @{ id = $script:POLICY_STATUS_CHECK }
            settings   = @{
                statusName               = $StatusContext
                invalidateOnSourceUpdate = $true
                scope                    = @($scope)
            }
        } | Out-Null
    }
}

#>
function Ensure-AdoRepoDeny {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectId,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$GroupDescriptor,
        
        [Parameter(Mandatory)]
        [int]$DenyBits
    )
    
    $token = "repoV2/$ProjectId/$RepoId"
    
    # Verify current permissions
    try {
        $currentAcl = Invoke-AdoRest GET "/_apis/securitynamespaces/$script:NS_GIT/accesscontrolentries?token=$([uri]::EscapeDataString($token))&descriptors=$([uri]::EscapeDataString($GroupDescriptor))"
        Write-Verbose "[AzureDevOps] Current ACL for group $GroupDescriptor"
        if ($currentAcl.value.Count -gt 0) {
            Write-Verbose "[AzureDevOps] Current permissions - Allow: $($currentAcl.value[0].allow), Deny: $($currentAcl.value[0].deny)"
        }
        else {
            Write-Verbose "[AzureDevOps] No existing permissions found for this group"
        }
    }
    catch {
        Write-Host "[WARN] Could not retrieve current ACL: $_" -ForegroundColor Yellow
    }
    
    # Apply deny permissions
    Write-Host "[INFO] Applying deny permissions (bits: $DenyBits) to group"
    Invoke-AdoRest POST "/_apis/securitynamespaces/$script:NS_GIT/accesscontrolentries" -Body @{
        token                = $token
        merge                = $true
        accessControlEntries = @(@{
                descriptor = $GroupDescriptor
                allow      = 0
                deny       = $DenyBits
            })
    } | Out-Null
    Write-Host "[INFO] Deny permissions successfully applied" -ForegroundColor Green
}

#>
function Ensure-AdoRepoFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId,
        
        [Parameter(Mandatory)]
        [string]$RepoName,
        
        [ValidateSet('dotnet', 'node', 'python', 'java', 'all')]
        [string]$ProjectType = 'all'
    )
    
    Write-Host "[INFO] Creating enhanced repository files..." -ForegroundColor Cyan
    
    # Get default branch
    try {
        $repo = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
        $defaultBranch = $repo.defaultBranch -replace '^refs/heads/', ''
    }
    catch {
        Write-Warning "Could not determine default branch, using 'main'"
        $defaultBranch = 'main'
    }
    
    # .gitignore content
    $gitignoreContent = @"
# Gitlab2DevOps - Enhanced .gitignore
# Generated for project type: $ProjectType

## User-specific files
*.suo
*.user
*.userosscache
*.sln.docstates
.vscode/
.idea/
*.swp
*.swo
*~

## Build results
[Dd]ebug/
[Rr]elease/
x64/
x86/
[Bb]in/
[Oo]bj/
[Ll]og/
[Ll]ogs/
*.log
build/
dist/
out/

## .NET
*.dll
*.exe
*.pdb
*.cache
project.lock.json
project.fragment.lock.json
artifacts/
**/Properties/launchSettings.json
TestResults/
*.VisualState.xml

## Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.npm
.eslintcache
.node_repl_history
*.tgz
.yarn-integrity
.env.local
.env.*.local

## Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
ENV/
.venv
pip-log.txt
pip-delete-this-directory.txt
.pytest_cache/
*.egg-info/
.coverage
htmlcov/

## Java
*.class
*.jar
*.war
*.ear
target/
.gradle/
gradle-app.setting
.gradletasknamecache
hs_err_pid*

## OS
.DS_Store
Thumbs.db
Desktop.ini

## Environment & Secrets (CRITICAL)
.env
.env.local
.env.*.local
appsettings.Development.json
appsettings.Local.json
secrets.json
*.pfx
*.key
*.pem

## Databases
*.db
*.sqlite
*.sqlite3

## Package managers
package-lock.json
yarn.lock
Gemfile.lock
poetry.lock
Pipfile.lock

## IDEs
.vs/
.vscode/settings.json
.idea/
*.iml
*.iws

## Temporary files
*.tmp
*.temp
*.bak
*.swp
*~

## Azure
local.settings.json
.azure/
"@

    # .editorconfig content
    $editorconfigContent = @"
# EditorConfig - Consistent coding styles
# https://editorconfig.org

root = true

# All files
[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

# Code files
[*.{cs,csx,vb,vbx,js,ts,jsx,tsx,java,py}]
indent_style = space
indent_size = 4

# JSON, YAML, XML
[*.{json,yml,yaml,xml,csproj,props,targets}]
indent_style = space
indent_size = 2

# Markdown
[*.md]
trim_trailing_whitespace = false
max_line_length = 120

# Shell scripts
[*.{sh,bash,zsh}]
indent_style = space
indent_size = 2
end_of_line = lf

# Batch files
[*.{cmd,bat}]
end_of_line = crlf

# C# specific
[*.cs]
# Organize usings
dotnet_sort_system_directives_first = true
dotnet_separate_import_directive_groups = false

# this. preferences
dotnet_style_qualification_for_field = false:warning
dotnet_style_qualification_for_property = false:warning
dotnet_style_qualification_for_method = false:warning
dotnet_style_qualification_for_event = false:warning

# Language keywords vs BCL types
dotnet_style_predefined_type_for_locals_parameters_members = true:warning
dotnet_style_predefined_type_for_member_access = true:warning

# Parentheses preferences
dotnet_style_parentheses_in_arithmetic_binary_operators = always_for_clarity:warning
dotnet_style_parentheses_in_other_binary_operators = always_for_clarity:warning

# Expression preferences
dotnet_style_prefer_auto_properties = true:suggestion
dotnet_style_prefer_inferred_tuple_names = true:suggestion
dotnet_style_prefer_inferred_anonymous_type_member_names = true:suggestion

# Null checking
csharp_style_throw_expression = true:suggestion
csharp_style_conditional_delegate_call = true:suggestion

# var preferences
csharp_style_var_for_built_in_types = true:suggestion
csharp_style_var_when_type_is_apparent = true:suggestion
csharp_style_var_elsewhere = true:suggestion

# Expression-bodied members
csharp_style_expression_bodied_methods = when_on_single_line:suggestion
csharp_style_expression_bodied_constructors = false:suggestion
csharp_style_expression_bodied_operators = when_on_single_line:suggestion
csharp_style_expression_bodied_properties = when_on_single_line:suggestion

# Pattern matching
csharp_style_pattern_matching_over_is_with_cast_check = true:suggestion
csharp_style_pattern_matching_over_as_with_null_check = true:suggestion

# Null checking preferences
csharp_style_inlined_variable_declaration = true:suggestion

# Code block preferences
csharp_prefer_braces = true:warning

# JavaScript/TypeScript
[*.{js,ts,jsx,tsx}]
quote_type = single
indent_style = space
indent_size = 2

# Python
[*.py]
indent_style = space
indent_size = 4
max_line_length = 88
"@

    # Create files via Git push API
    $filesCreated = @()
    
    try {
        # Get latest commit
        $refs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$defaultBranch"
        if ($refs.value.Count -eq 0) {
            Write-Warning "Repository has no commits yet. Files will be added after first push."
            return
        }
        
        $latestCommit = $refs.value[0].objectId
        
        # Prepare push with all files
        $changes = @()
        
        # Add .gitignore if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.gitignore"
            Write-Host "  ✓ .gitignore already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.gitignore" }
                newContent = @{
                    content = $gitignoreContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add .editorconfig if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.editorconfig"
            Write-Host "  ✓ .editorconfig already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.editorconfig" }
                newContent = @{
                    content = $editorconfigContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Push all changes if any
        if ($changes.Count -gt 0) {
            $pushPayload = @{
                refUpdates = @(
                    @{
                        name = "refs/heads/$defaultBranch"
                        oldObjectId = $latestCommit
                    }
                )
                commits = @(
                    @{
                        comment = "Add enhanced repository files (gitignore, editorconfig, CONTRIBUTING, CODEOWNERS)"
                        changes = $changes
                    }
                )
            }
            
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushPayload | Out-Null
            Write-Host "[SUCCESS] Created repository files: $($changes.Count) file(s)" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] All repository files already exist" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Failed to create repository files: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Ensure-AdoRepositoryTemplates',
    'Ensure-AdoRepository',
    'Get-AdoRepoDefaultBranch',
    'Ensure-AdoBranchPolicies',
    'Ensure-AdoRepoDeny',
    'Ensure-AdoRepoFiles'
)
