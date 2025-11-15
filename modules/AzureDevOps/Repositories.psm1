<#
.SYNOPSIS
    Repository management and branch policies

.DESCRIPTION
    Part of Gitlab2DevOps - AzureDevOps module
    Version: 2.1.0
#>

#Requires -Version 5.1
Set-StrictMode -Version Latest


function New-AdoRepositoryTemplates {
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
        $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/commits?``$top=1" -ReturnNullOnNotFound
        $hasCommits = $commits.count -gt 0
    }
    catch {
        Write-LogLevelVerbose "[New-AdoRepositoryTemplates] Could not check commits: $_"
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
    
    # Define template files - load from external templates
    $readmeTemplatePath = Join-Path $PSScriptRoot "..\templates\README.template.md"
    if (-not (Test-Path $readmeTemplatePath)) {
        Write-Error "[New-AdoRepositoryTemplates] README template not found: $readmeTemplatePath"
        return
    }
    $readmeTemplate = Get-Content -Path $readmeTemplatePath -Raw -Encoding UTF8
    $readmeContent = $readmeTemplate -replace '{{REPO_NAME}}', $RepoName

    # Load PR template
    $prTemplatePath = Join-Path $PSScriptRoot "..\templates\PullRequestTemplate.md"
    if (-not (Test-Path $prTemplatePath)) {
        Write-Error "[New-AdoRepositoryTemplates] PR template not found: $prTemplatePath"
        return
    }
    $prTemplateContent = Get-Content -Path $prTemplatePath -Raw -Encoding UTF8

    $filesCreated = @()
    $createdCount = 0
    $skippedCount = 0
    
    # Check and create README.md
    try {
        $existingReadme = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/README.md" -ReturnNullOnNotFound
        if ($existingReadme) {
            Write-Host "[INFO] README.md already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-LogLevelVerbose "[New-AdoRepositoryTemplates] Creating README.md"
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
        $existingPR = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.azuredevops/pull_request_template.md" -ReturnNullOnNotFound
        if ($existingPR) {
            Write-Host "[INFO] PR template already exists" -ForegroundColor Gray
            $skippedCount++
        }
    }
    catch {
        # File doesn't exist, create it
        try {
            Write-LogLevelVerbose "[New-AdoRepositoryTemplates] Creating .azuredevops/pull_request_template.md"
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


function New-AdoRepository {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$ProjId,
        
        [Parameter(Mandatory)]
        [ValidateScript({
            Test-AdoRepositoryName $_ -ThrowOnError
            $true
        })]
        [string]$RepoName,
        
        [switch]$AllowExisting,
        
        [switch]$Replace
    )
    
    Write-LogLevelVerbose "[New-AdoRepository] Checking if repository '$RepoName' exists..."
    
    $repos = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -ReturnNullOnNotFound
    $existing = $repos.value | Where-Object { $_.name -eq $RepoName }
    
    if ($existing) {
        Write-LogLevelVerbose "[New-AdoRepository] Repository '$RepoName' exists (ID: $($existing.id))"
        
        # Check if repository has commits
        try {
            $commits = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$($existing.id)/commits?``$top=1"
            $hasCommits = $commits.count -gt 0
        }
        catch {
            $hasCommits = $false
        }
        
        if ($hasCommits) {
            Write-LogLevelVerbose "[New-AdoRepository] Repository has $($commits.count) commit(s)"
            
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
    Write-Host "[INFO] Creating new repository: $RepoName" -ForegroundColor Cyan
    $newRepo = Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories" -Body @{
        name    = $RepoName
        project = @{ id = $ProjId }
    }
    Write-Host "[SUCCESS] Repository '$RepoName' created successfully" -ForegroundColor Green
    return $newRepo
}


function Remove-AdoDefaultRepository {
    <#
    .SYNOPSIS
        Removes the auto-created default repository from a newly provisioned Azure DevOps project.

    .DESCRIPTION
        Newly created Azure DevOps projects ship with a single Git repository whose name matches the
        project. This helper deletes that default repository when it is the only repository present
        and still empty (zero or one commits), allowing migration workflows to recreate repositories
        with clean history.

    .PARAMETER Project
        Azure DevOps project name.

    .PARAMETER ProjId
        Azure DevOps project ID (GUID).

    .OUTPUTS
        [bool] True when a repository was deleted, otherwise False.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Project,

        [Parameter(Mandatory)]
        [string]$ProjId
    )

    if ($env:GITLAB2DEVOPS_SKIP_DEFAULT_REPO_DELETE -and $env:GITLAB2DEVOPS_SKIP_DEFAULT_REPO_DELETE -match '^(1|true)$') {
        Write-Host "[INFO] Skip flag detected (GITLAB2DEVOPS_SKIP_DEFAULT_REPO_DELETE). Default repository will not be removed." -ForegroundColor Yellow
        return $false
    }

    try {
        $projectEscaped = [uri]::EscapeDataString($Project)
        $repoList = Invoke-AdoRest GET "/$projectEscaped/_apis/git/repositories" -ReturnNullOnNotFound
        if (-not $repoList -or -not $repoList.value -or $repoList.value.Count -lt 1) {
            return $false
        }

        $repos = $repoList.value
        if ($repos.Count -le 1) {
            Write-LogLevelVerbose "[Remove-AdoDefaultRepository] Only one repository present in '$Project'. Skipping deletion to satisfy minimum threshold."
            return $false
        }

        $defaultRepo = $repos | Where-Object { $_.name -eq $Project } | Select-Object -First 1
        if (-not $defaultRepo) {
            Write-LogLevelVerbose "[Remove-AdoDefaultRepository] No default repository matching project name '$Project' found."
            return $false
        }

        # Ensure this is the auto-created repo (same project, matching name)
        if ($defaultRepo.name -ne $Project -or `
            -not $defaultRepo.project -or `
            $defaultRepo.project.id -ne $ProjId) {
            return $false
        }

        # If repository already has more than one commit, treat it as user content and skip removal
        $commitCount = 0
        try {
            $commits = Invoke-AdoRest GET "/$projectEscaped/_apis/git/repositories/$($defaultRepo.id)/commits?`$top=2"
            if ($commits -and $commits.count) {
                $commitCount = [int]$commits.count
            }
        }
        catch {
            Write-Verbose "[Remove-AdoDefaultRepository] Unable to determine commit count: $_"
        }

        if ($commitCount -gt 1) {
            Write-Verbose "[Remove-AdoDefaultRepository] Repository '$($defaultRepo.name)' has more than one commit. Skipping deletion to avoid data loss."
            return $false
        }

        Write-Host "[INFO] Removing default repository '$($defaultRepo.name)' from project '$Project'..." -ForegroundColor Yellow
        Invoke-AdoRest DELETE "/$projectEscaped/_apis/git/repositories/$($defaultRepo.id)" | Out-Null
        Start-Sleep -Seconds 2
        Write-Host "[SUCCESS] Default repository removed." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "[Remove-AdoDefaultRepository] Failed to remove default repository: $_"
        return $false
    }
}


function Get-AdoRepoDefaultBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId
    )
    
    try {
    $r = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId" -ReturnNullOnNotFound
        if ($r.PSObject.Properties['defaultBranch'] -and $r.defaultBranch) {
            Write-LogLevelVerbose "[Get-AdoRepoDefaultBranch] Found default branch: $($r.defaultBranch)"
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


function New-Adobranchpolicies {
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
    
    Write-LogLevelVerbose "[New-Adobranchpolicies] Checking existing policies for ref '$Ref'..."
    
    $cfgs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/policy/configurations"
    $scope = @{ repositoryId = $RepoId; refName = $Ref; matchKind = "exact" }

    # Ensure the target ref exists (repository has commits). If not, skip policies and log guidance.
    try {
        $refsCheck = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=$([uri]::EscapeDataString($Ref))"
        if (-not $refsCheck -or -not $refsCheck.value -or $refsCheck.value.Count -eq 0) {
            Write-Host "[INFO] Target ref '$Ref' not found - repository likely has no commits yet. Skipping branch policies until a default branch exists." -ForegroundColor Yellow
            Write-Host "  ▶️ After pushing the initial commit, re-run branch policy configuration or call New-Adobranchpolicies with the repo default ref." -ForegroundColor Gray
            return
        }
    }
    catch {
        Write-LogLevelVerbose "[New-Adobranchpolicies] Could not verify ref existence: $_"
        Write-Host "[INFO] Skipping branch policies due to inability to verify repository refs." -ForegroundColor Yellow
        return
    }
    
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
        Write-LogLevelVerbose "[New-Adobranchpolicies] Required reviewers policy already exists"
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
        Write-LogLevelVerbose "[New-Adobranchpolicies] Work item link policy already exists"
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
        Write-LogLevelVerbose "[New-Adobranchpolicies] Comment resolution policy already exists"
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
            Write-LogLevelVerbose "[New-Adobranchpolicies] Build validation policy already exists"
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


function Set-AdoRepoDeny {
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
        $currentAcl = Invoke-AdoRest GET "/_apis/securitynamespaces/$($script:NS_GIT)/accesscontrolentries?token=$([uri]::EscapeDataString($token))&descriptors=$([uri]::EscapeDataString($GroupDescriptor))"
        Write-LogLevelVerbose "[AzureDevOps] Current ACL for group $GroupDescriptor"
        if ($currentAcl.value.Count -gt 0) {
            Write-LogLevelVerbose "[AzureDevOps] Current permissions - Allow: $($currentAcl.value[0].allow), Deny: $($currentAcl.value[0].deny)"
        }
        else {
            Write-LogLevelVerbose "[AzureDevOps] No existing permissions found for this group"
        }
    }
    catch {
        Write-Host "[WARN] Could not retrieve current ACL: $_" -ForegroundColor Yellow
    }
    
    # Apply deny permissions
    Write-Host "[INFO] Applying deny permissions (bits: $DenyBits) to group"
Invoke-AdoRest POST "/_apis/securitynamespaces/$($script:NS_GIT)/accesscontrolentries" -Body @{
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


function New-AdoRepoFiles {
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
        if ($repo -and $repo.PSObject.Properties['defaultBranch'] -and $repo.defaultBranch) {
            $defaultBranch = $repo.defaultBranch -replace '^refs/heads/', ''
        }
        else {
            Write-Warning "Repository has no default branch set, using 'main'"
            $defaultBranch = 'main'
        }
    }
    catch {
        Write-Warning "Could not determine default branch, using 'main'"
        $defaultBranch = 'main'
    }
    
    # .gitignore content - load from template
    $gitignoreTemplatePath = Join-Path $PSScriptRoot "..\templates\gitignore.template"
    if (-not (Test-Path $gitignoreTemplatePath)) {
        Write-Error "[New-AdoRepoFiles] Gitignore template not found: $gitignoreTemplatePath"
        return
    }
    $gitignoreTemplate = Get-Content -Path $gitignoreTemplatePath -Raw -Encoding UTF8
    $gitignoreContent = $gitignoreTemplate -replace '{{PROJECT_TYPE}}', $ProjectType

    # .editorconfig content - load from template
    $editorconfigTemplatePath = Join-Path $PSScriptRoot "..\templates\editorconfig.template"
    if (-not (Test-Path $editorconfigTemplatePath)) {
        Write-Error "[New-AdoRepoFiles] Editorconfig template not found: $editorconfigTemplatePath"
        return
    }
    $editorconfigContent = Get-Content -Path $editorconfigTemplatePath -Raw -Encoding UTF8

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
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.gitignore" -ReturnNullOnNotFound
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
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.editorconfig" -ReturnNullOnNotFound
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

#
# Backwards-compatible wrapper: Ensure-AdoRepoFiles
# Some tests and older callers expect Ensure-AdoRepoFiles to exist. Delegate to New-AdoRepoFiles.
#
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

    Write-LogLevelVerbose "[Ensure-AdoRepoFiles] Delegating to New-AdoRepoFiles"
    return New-AdoRepoFiles -Project $Project -RepoId $RepoId -RepoName $RepoName -ProjectType $ProjectType
}


function New-AdoSecurityRepoFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Project,
        
        [Parameter(Mandatory)]
        [string]$RepoId
    )
    
    Write-Host "[INFO] Adding security repository files..." -ForegroundColor Cyan
    
    # Get default branch
    try {
        $repo = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId"
        if ($repo -and $repo.PSObject.Properties['defaultBranch'] -and $repo.defaultBranch) {
            $defaultBranch = $repo.defaultBranch -replace '^refs/heads/', ''
        }
        else {
            Write-Warning "Repository has no default branch set, using 'main'"
            $defaultBranch = 'main'
        }
    }
    catch {
        Write-Warning "Could not determine default branch, using 'main'"
        $defaultBranch = 'main'
    }
    
    # SECURITY.md content
    $securityMdContent = @"
# Security Policy

## Reporting Security Vulnerabilities

**DO NOT** create public issues for security vulnerabilities.

Instead, please report security issues to: **security@example.com**

### What to Include
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if available)

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |
| < Latest| :x:                |

## Security Best Practices

### Code Review
- All code changes require review
- Security-sensitive changes require security team review
- Check for common vulnerabilities (SQL injection, XSS, CSRF, etc.)

### Dependency Management
- Keep dependencies up to date
- Run security scans regularly
- Review dependency licenses
- Use Dependabot/Renovate for automated updates

### Authentication & Authorization
- Never hardcode credentials
- Use Azure Key Vault for secrets
- Implement least privilege access
- Use multi-factor authentication

### Data Protection
- Encrypt sensitive data at rest and in transit
- Implement proper input validation
- Sanitize user inputs
- Use parameterized queries

## Security Scanning

This repository uses automated security scanning:
- **Trivy**: Container and dependency scanning
- **Snyk**: Vulnerability detection
- **CodeQL**: Static analysis (if enabled)

## Incident Response

In case of a security incident:
1. Report immediately to security team
2. Do not discuss publicly
3. Preserve evidence
4. Follow incident response plan
"@

    # security-scan-config.yml content
    $securityScanConfigContent = @"
# Security Scanning Configuration
# Used by CI/CD pipelines for automated security checks

scan_types:
  - dependency_check
  - secret_scan
  - container_scan
  - static_analysis

severity_threshold: MEDIUM  # Fail on MEDIUM, HIGH, CRITICAL

trivy:
  enabled: true
  ignore_unfixed: false
  scan_refs: main,develop,release/*
  
snyk:
  enabled: true
  fail_on_issues: true
  monitor: true
  
secret_scanning:
  enabled: true
  patterns:
    - api[_-]?key
    - password
    - secret
    - token
    - private[_-]?key
  exclude_paths:
    - "**/*.md"
    - "**/test/**"
    - "**/tests/**"

reporting:
  upload_to_defect_dojo: false
  create_work_items: true
  notify_security_team: true
"@

    # .trivyignore content
    $trivyIgnoreContent = @"
# Trivy Ignore File
# Add CVE IDs or vulnerability IDs to suppress false positives
# Format: CVE-YYYY-NNNN or GHSA-xxxx-xxxx-xxxx

# Example: Suppress known false positive
# CVE-2024-12345

# Example: Suppress vulnerability with mitigation in place
# GHSA-1234-5678-9abc  # Mitigated by WAF rules
"@

    # .snyk content
    $snykContent = @"
# Snyk configuration file
# Learn more: https://docs.snyk.io/snyk-cli/test-for-vulnerabilities/the-.snyk-file

version: v1.25.0

# Ignore specific vulnerabilities
ignore: {}

# Example:
# ignore:
#   'npm:lodash:20210201':
#     - '*':
#         reason: 'Mitigated in our usage context'
#         expires: '2025-12-31'

# Patch specific vulnerabilities
patch: {}

# Language-specific settings
language-settings: {}
"@

    # Check repository has commits
    try {
        $refs = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/refs?filter=heads/$defaultBranch"
        if ($refs.value.Count -eq 0) {
            Write-Warning "Repository has no commits yet. Security files will be added after first push."
            return
        }
        
        $latestCommit = $refs.value[0].objectId
        
        # Prepare push with security files
        $changes = @()
        
        # Add SECURITY.md if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/SECURITY.md" -ReturnNullOnNotFound
            Write-Host "  ✓ SECURITY.md already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/SECURITY.md" }
                newContent = @{
                    content = $securityMdContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add security-scan-config.yml if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/security-scan-config.yml" -ReturnNullOnNotFound
            Write-Host "  ✓ security-scan-config.yml already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/security-scan-config.yml" }
                newContent = @{
                    content = $securityScanConfigContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add .trivyignore if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.trivyignore" -ReturnNullOnNotFound
            Write-Host "  ✓ .trivyignore already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.trivyignore" }
                newContent = @{
                    content = $trivyIgnoreContent
                    contentType = "rawtext"
                }
            }
        }
        
        # Add .snyk if not exists
        try {
            $existing = Invoke-AdoRest GET "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/items?path=/.snyk" -ReturnNullOnNotFound
            Write-Host "  ✓ .snyk already exists" -ForegroundColor Gray
        }
        catch {
            $changes += @{
                changeType = "add"
                item = @{ path = "/.snyk" }
                newContent = @{
                    content = $snykContent
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
                        comment = "Add security repository files (SECURITY.md, scanning configs)"
                        changes = $changes
                    }
                )
            }
            
            Invoke-AdoRest POST "/$([uri]::EscapeDataString($Project))/_apis/git/repositories/$RepoId/pushes" -Body $pushPayload | Out-Null
            Write-Host "[SUCCESS] Created security files: $($changes.Count) file(s)" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] All security files already exist" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Failed to create security repository files: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'New-AdoRepositoryTemplates',
    'New-AdoRepository',
    'Remove-AdoDefaultRepository',
    'Get-AdoRepoDefaultBranch',
    'New-Adobranchpolicies',
    'Set-AdoRepoDeny',
    'New-AdoRepoFiles',
    'New-AdoSecurityRepoFiles'
)

