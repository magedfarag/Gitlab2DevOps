# Publishing to GitHub - Step-by-Step Guide

## Pre-Publication Checklist

### ✅ Files to Review Before Publishing

1. **Core Script**: `devops.ps1` (2146 lines)
2. **Documentation**:
   - README.md
   - SYNC_MODE_GUIDE.md
   - QUICK_REFERENCE.md
   - BULK_MIGRATION_CONFIG.md
   - CHANGELOG.md
   - CONTRIBUTING.md
   - PROJECT_SUMMARY.md
   - LICENSE
3. **Templates**:
   - bulk-migration-config.template.json
   - setup-env.template.ps1
4. **GitHub Templates**:
   - .github/ISSUE_TEMPLATE/bug_report.md
   - .github/ISSUE_TEMPLATE/feature_request.md
   - .github/ISSUE_TEMPLATE/question.md
   - .github/PULL_REQUEST_TEMPLATE.md
5. **Git Configuration**:
   - .gitignore (migrations folder excluded)
   - .gitattributes

---

## Step 1: Verify Git Status

```powershell
# Navigate to project directory
cd C:\Projects\devops\Gitlab2DevOps

# Check current status
git status

# Check current branch
git branch

# Ensure you're on main branch
git checkout main
```

---

## Step 2: Review Changes

```powershell
# See what files have changed
git status

# Review specific file changes
git diff devops.ps1
git diff README.md

# See list of new files
git ls-files --others --exclude-standard
```

**Expected New Files:**
- SYNC_MODE_GUIDE.md
- SYNC_IMPLEMENTATION_SUMMARY.md
- COMMIT_MESSAGE.md
- GITHUB_RELEASE_NOTES.md
- PUBLISHING_GUIDE.md

**Expected Modified Files:**
- devops.ps1 (~150 lines changed)
- README.md (sync section added)
- QUICK_REFERENCE.md (sync examples)
- CHANGELOG.md (v2.0.0 updates)

---

## Step 3: Stage Changes

```powershell
# Stage all changes (recommended)
git add .

# OR stage selectively:
git add devops.ps1
git add README.md QUICK_REFERENCE.md CHANGELOG.md
git add SYNC_MODE_GUIDE.md
git add SYNC_IMPLEMENTATION_SUMMARY.md
git add COMMIT_MESSAGE.md GITHUB_RELEASE_NOTES.md PUBLISHING_GUIDE.md

# Verify staged files
git status
```

---

## Step 4: Commit Changes

### Option A: Using Prepared Commit Message File
```powershell
# Use the detailed commit message
git commit -F COMMIT_MESSAGE.md
```

### Option B: Direct Commit Message
```powershell
git commit -m "feat: Add sync mode for repository updates" -m "
- Add -AllowSync parameter to enable re-running migrations
- Track migration history with type, count, and timestamps
- Preserve Azure DevOps settings while updating content
- Add comprehensive documentation (SYNC_MODE_GUIDE.md)
- Update README, QUICK_REFERENCE, and CHANGELOG

Enables keeping ADO repos synchronized with GitLab updates
while preserving policies, permissions, and configurations.

Features Added:
* Sync mode for single and bulk migrations
* Migration history tracking with previous_migrations array
* Non-destructive repository updates
* Interactive menu prompts for sync mode
* Complete documentation suite

Modified Functions:
- Ensure-Repo: Added -AllowExisting switch
- New-MigrationPreReport: Added sync validation
- Migrate-One: Added history tracking
- Bulk-Migrate-FromConfig: Added sync support
- Bulk-Migrate: Added sync support

Documentation:
- Created SYNC_MODE_GUIDE.md (364 lines)
- Updated README.md with sync section
- Updated QUICK_REFERENCE.md with sync examples
- Updated CHANGELOG.md with v2.0.0 features

Co-authored-by: GitHub Copilot <noreply@github.com>
"
```

### Option C: Interactive Commit (Manual)
```powershell
git commit
# Your default editor will open
# Copy content from COMMIT_MESSAGE.md
```

---

## Step 5: Verify Commit

```powershell
# View the commit
git log -1

# See what was committed
git show HEAD

# View commit stats
git log -1 --stat
```

---

## Step 6: Create Git Tag for v2.0.0

```powershell
# Create annotated tag
git tag -a v2.0.0 -m "Version 2.0.0: Enterprise Security + Sync Mode

Major Features:
- Sync mode for re-running migrations
- Migration history tracking
- Enterprise security enhancements
- Enhanced bulk migration config format
- Comprehensive documentation

See GITHUB_RELEASE_NOTES.md for full details."

# Verify tag was created
git tag -l

# View tag details
git show v2.0.0
```

---

## Step 7: Push to GitHub

### Push Commits
```powershell
# Push to main branch
git push origin main

# If this is first push or upstream not set:
git push -u origin main
```

### Push Tags
```powershell
# Push the v2.0.0 tag
git push origin v2.0.0

# OR push all tags:
git push origin --tags
```

---

## Step 8: Create GitHub Release

### Option A: Using GitHub Web Interface

1. **Navigate to Repository**:
   - Go to: https://github.com/magedfarag/Gitlab2DevOps

2. **Create Release**:
   - Click "Releases" in right sidebar
   - Click "Draft a new release"
   - Choose tag: `v2.0.0`
   - Release title: `v2.0.0 - Enterprise Security & Sync Mode`
   - Description: Copy content from `GITHUB_RELEASE_NOTES.md`
   - Check "Set as the latest release"
   - Click "Publish release"

### Option B: Using GitHub CLI (if installed)

```powershell
# Install GitHub CLI if needed:
# winget install GitHub.cli

# Authenticate
gh auth login

# Create release from notes file
gh release create v2.0.0 `
  --title "v2.0.0 - Enterprise Security & Sync Mode" `
  --notes-file GITHUB_RELEASE_NOTES.md `
  --latest

# OR create release with inline notes
gh release create v2.0.0 `
  --title "v2.0.0 - Enterprise Security & Sync Mode" `
  --notes "Major release with sync mode and security enhancements. See full notes at: https://github.com/magedfarag/Gitlab2DevOps/blob/main/GITHUB_RELEASE_NOTES.md"
```

---

## Step 9: Update Repository Settings (GitHub Web)

### 1. Update Repository Description
- Go to repository homepage
- Click "⚙️ Settings" (top right, under repository name)
- Update description: `Enterprise-grade GitLab to Azure DevOps migration tool with sync capabilities`
- Add topics/tags: `gitlab`, `azure-devops`, `migration`, `powershell`, `devops`, `sync`

### 2. Set Default Branch (if needed)
- Settings → Branches
- Ensure default branch is `main`

### 3. Configure Branch Protection (recommended)
- Settings → Branches
- Add rule for `main` branch:
  - ✅ Require pull request reviews before merging
  - ✅ Require status checks to pass before merging
  - ✅ Require conversation resolution before merging
  - ✅ Do not allow bypassing the above settings

### 4. Enable Issues & Discussions
- Settings → General
- ✅ Issues
- ✅ Discussions (optional, for Q&A)

### 5. Set License
- Verify LICENSE file is detected
- Should show "MIT License" on repository homepage

---

## Step 10: Post-Publication Verification

### Verify on GitHub:

```powershell
# Check remote status
git remote -v

# Verify push was successful
git log origin/main -1

# Check tag exists remotely
git ls-remote --tags origin
```

### On GitHub Website:

1. **Main Page**:
   - ✅ README.md displays correctly
   - ✅ License badge shows MIT
   - ✅ Topics/tags visible
   - ✅ Latest commit shows sync feature

2. **Releases**:
   - ✅ v2.0.0 release is visible
   - ✅ Release notes formatted correctly
   - ✅ Marked as "Latest"

3. **Code Browser**:
   - ✅ All new files present (SYNC_MODE_GUIDE.md, etc.)
   - ✅ .github templates visible
   - ✅ migrations/ folder NOT in repository (gitignored)

4. **Issues**:
   - ✅ Templates available when creating new issue
   - ✅ Bug report template works
   - ✅ Feature request template works
   - ✅ Question template works

---

## Step 11: Announce Release (Optional)

### Update README Badge (if you have one)
```markdown
[![Latest Release](https://img.shields.io/github/v/release/magedfarag/Gitlab2DevOps)](https://github.com/magedfarag/Gitlab2DevOps/releases/latest)
```

### Create Announcement
- Post in GitHub Discussions (if enabled)
- Share on relevant platforms
- Update any documentation pointing to the tool

### Example Announcement:
```markdown
# 🎉 v2.0.0 Released - Sync Mode & Enterprise Security

We're excited to announce v2.0.0 of the GitLab to Azure DevOps Migration Tool!

**Major Features:**
🔄 Sync Mode - Re-run migrations to keep ADO repos updated with GitLab changes
📊 Migration History - Complete audit trail of all sync operations
🔒 Enterprise Security - Zero hardcoded credentials, SSL support, configurable APIs
📦 Enhanced Bulk Migrations - Improved config format with preparation status

**Fully Backward Compatible** - Existing scripts work without changes!

📖 Docs: https://github.com/magedfarag/Gitlab2DevOps
🚀 Quick Start: See README.md
🔄 Sync Guide: See SYNC_MODE_GUIDE.md

Download now: https://github.com/magedfarag/Gitlab2DevOps/releases/tag/v2.0.0
```

---

## Rollback Plan (If Needed)

If you need to undo the publication:

### Undo Local Commit (before push):
```powershell
# Undo last commit, keep changes staged
git reset --soft HEAD~1

# Undo last commit, keep changes unstaged
git reset HEAD~1

# Undo last commit, discard changes (dangerous!)
git reset --hard HEAD~1
```

### Undo After Push:
```powershell
# Create revert commit
git revert HEAD
git push origin main

# OR force push previous commit (dangerous for public repos!)
git reset --hard HEAD~1
git push origin main --force
```

### Delete Tag:
```powershell
# Delete local tag
git tag -d v2.0.0

# Delete remote tag
git push origin --delete v2.0.0
```

### Delete Release:
- Go to GitHub → Releases
- Click release → "Delete release" button
- Confirm deletion

---

## Troubleshooting

### "Failed to push some refs"
```powershell
# Pull latest changes first
git pull origin main --rebase

# Then push again
git push origin main
```

### "Tag already exists"
```powershell
# Delete existing tag
git tag -d v2.0.0
git push origin --delete v2.0.0

# Recreate tag
git tag -a v2.0.0 -m "Your message"
git push origin v2.0.0
```

### "Authentication failed"
```powershell
# Use GitHub personal access token
git config credential.helper manager-core

# Next push will prompt for credentials
# Use your GitHub PAT as password
```

### Large files warning
```powershell
# If migrations folder accidentally committed:
git rm -r --cached migrations/
git commit -m "Remove migrations folder"
git push origin main
```

---

## Final Checklist

Before marking publication complete:

- [ ] All changes committed with proper message
- [ ] v2.0.0 tag created and pushed
- [ ] Changes pushed to main branch
- [ ] GitHub release created with notes
- [ ] README displays correctly on GitHub
- [ ] All documentation files accessible
- [ ] Issue templates work
- [ ] License detected correctly
- [ ] No sensitive data committed (PATs, credentials)
- [ ] migrations/ folder properly gitignored
- [ ] Repository description and topics updated

---

## Quick Command Summary

```powershell
# Complete publication in one go:
cd C:\Projects\devops\Gitlab2DevOps
git status
git add .
git commit -F COMMIT_MESSAGE.md
git tag -a v2.0.0 -m "Version 2.0.0: Enterprise Security + Sync Mode"
git push origin main
git push origin v2.0.0

# Then create GitHub release via web interface using GITHUB_RELEASE_NOTES.md
```

---

## Post-Publication Maintenance

### Keep Repository Updated:
```powershell
# Regular workflow
git pull origin main
# Make changes
git add .
git commit -m "description"
git push origin main
```

### For Bug Fixes:
```powershell
# Create branch
git checkout -b fix/issue-name
# Make fixes
git add .
git commit -m "fix: description"
git push origin fix/issue-name
# Create PR on GitHub
```

### For New Features:
```powershell
# Create branch
git checkout -b feature/feature-name
# Develop feature
git add .
git commit -m "feat: description"
git push origin feature/feature-name
# Create PR on GitHub
```

---

**Ready to publish? Follow the steps above in order!**

Good luck with your v2.0.0 release! 🚀
