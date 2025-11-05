# Publishing Guide

This guide provides step-by-step instructions for publishing releases of the GitLab to Azure DevOps Migration Tool.

## Pre-Publication Checklist

### 1. Verify Readiness

Run the pre-publication verification script:
```powershell
.\verify-publication-ready.ps1
```

This script checks:
- ✅ Core files exist and are properly configured
- ✅ Documentation is complete and up-to-date
- ✅ GitHub templates are in place
- ✅ Test suite passes
- ✅ No uncommitted changes
- ✅ No sensitive data in tracked files

### 2. Version Planning

Before publishing, ensure:
- [ ] Version number follows [Semantic Versioning](https://semver.org/)
- [ ] CHANGELOG.md is updated with new version
- [ ] Breaking changes are documented
- [ ] Migration guide is provided if needed

### 3. Testing Validation

Run the complete test suite:
```powershell
# Run offline tests
Invoke-Pester .\tests\OfflineTests.ps1 -Verbose

# Run extended tests  
Invoke-Pester .\tests\ExtendedTests.ps1 -Verbose

# Generate coverage report
Invoke-Pester -Configuration @{
    Run = @{ Path = '.\tests\*.Tests.ps1' }
    CodeCoverage = @{ 
        Enabled = $true
        Path = '.\modules\*.psm1'
        OutputFormat = 'JaCoCo'
    }
    TestResult = @{ Enabled = $true; OutputFormat = 'NUnitXml' }
}
```

Expected results:
- 🎯 **83 tests** should pass (29 offline + 54 extended)
- 🎯 **100% pass rate** required for publication
- 🎯 **Code coverage** should be documented

## Publication Process

### Step 1: Prepare Release Content

#### Update Version Information
1. **Update main script version**:
   ```powershell
   # In Gitlab2DevOps.ps1, update version in header comment
   # GitLab to Azure DevOps Migration Tool v2.0.0
   ```

2. **Update CHANGELOG.md**:
   - Move items from `[Unreleased]` to new version section
   - Add release date
   - Create new `[Unreleased]` section for future changes

3. **Update PROJECT_SUMMARY.md**:
   - Update version number in footer
   - Update "Last Updated" date
   - Review technical information for accuracy

#### Prepare Release Messages
1. **Review COMMIT_MESSAGE.md**:
   - Ensure it accurately reflects the release content
   - Update version number in title
   - Verify feature list is complete

2. **Review GITHUB_RELEASE_NOTES.md**:
   - Ensure all new features are documented
   - Include upgrade/migration instructions
   - Add any breaking change warnings

### Step 2: Create Git Release

#### Stage and Commit Changes
```powershell
# Review what will be committed
git status

# Stage all changes
git add .

# Commit using the prepared message
git commit -F COMMIT_MESSAGE.md

# Verify commit looks correct
git log -1 --oneline
```

#### Create and Push Tags
```powershell
# Create annotated tag
git tag -a v2.0.0 -m "Version 2.0.0 - Sync Mode and Enterprise Reliability"

# Push commits and tags
git push origin main
git push origin v2.0.0

# Verify tag was created
git tag -l "v2.*"
```

### Step 3: GitHub Release

#### Create GitHub Release
1. **Navigate to GitHub**: Go to repository → Releases → "Create a new release"

2. **Configure Release**:
   - **Tag**: Select the tag you just pushed (e.g., `v2.0.0`)
   - **Title**: Copy from COMMIT_MESSAGE.md first line
   - **Description**: Copy content from GITHUB_RELEASE_NOTES.md

3. **Release Options**:
   - [ ] ✅ **Set as latest release** (for stable releases)
   - [ ] ⚠️ **Set as pre-release** (for beta/RC versions)
   - [ ] 📝 **Generate release notes** (GitHub auto-generation - optional supplement)

4. **Publish**: Click "Publish release"

### Step 4: Post-Publication Verification

#### Verify Release
1. **Check GitHub Release Page**:
   - Verify release notes display correctly
   - Confirm download links work
   - Check that version badge updates (if used)

2. **Test Download and Installation**:
   ```powershell
   # In a clean directory
   git clone https://github.com/your-org/gitlab2devops.git -b v2.0.0
   cd gitlab2devops
   .\verify-publication-ready.ps1
   ```

3. **Update Documentation Links**:
   - Verify README.md links work in GitHub view
   - Ensure examples in documentation are accurate
   - Check that all referenced files exist

## Hotfix Process

For critical bug fixes that need immediate release:

### 1. Create Hotfix Branch
```powershell
# From main branch
git checkout -b hotfix/v2.0.1

# Make minimal fixes
# ... edit files ...

# Test the fix
Invoke-Pester .\tests\OfflineTests.ps1
```

### 2. Expedited Release
```powershell
# Update CHANGELOG.md with hotfix details
# Update version in Gitlab2DevOps.ps1 comment

# Commit and tag
git add .
git commit -m "Hotfix v2.0.1: Critical SSL handling fix"
git tag -a v2.0.1 -m "Hotfix v2.0.1: Critical SSL handling fix"

# Merge to main and push
git checkout main
git merge hotfix/v2.0.1
git push origin main
git push origin v2.0.1
```

### 3. Create GitHub Hotfix Release
- Mark as "Latest Release"
- Include only the specific fixes
- Reference the original release for full features

## Communication Plan

### Internal Team
1. **Pre-Release**: Notify team of planned release timeline
2. **Release**: Share release notes and any deployment considerations
3. **Post-Release**: Provide usage metrics and feedback collection plan

### External Users
1. **Release Notes**: Clear communication of changes and migration steps
2. **Documentation**: Updated guides and examples
3. **Support**: Monitor for issues and provide prompt responses

## Rollback Procedure

If issues are discovered after publication:

### 1. Assess Impact
- Determine if issue affects all users or specific scenarios
- Evaluate if hotfix is sufficient or full rollback needed

### 2. Emergency Response
```powershell
# If rollback needed, delete problematic release
git tag -d v2.0.0
git push origin :refs/tags/v2.0.0

# Revert to previous stable release
git reset --hard v1.9.0
```

### 3. Communication
- Update GitHub release with warning/deprecation notice
- Provide clear guidance on recommended version to use
- Timeline for corrected release

## Best Practices

### Documentation
- Always test documentation examples before publishing
- Keep screenshots and examples current
- Verify all internal links work correctly

### Testing
- Never skip the verification script
- Test on clean environment to simulate new user experience
- Validate both CLI and interactive modes

### Communication
- Release notes should be accessible to non-technical users
- Include migration guides for any breaking changes
- Provide clear upgrade paths from previous versions

### Version Management
- Use semantic versioning consistently
- Tag releases immediately after testing
- Maintain CHANGELOG.md as single source of truth for changes

---

**Remember**: This is an enterprise tool. Reliability and clear communication are more important than speed of release.