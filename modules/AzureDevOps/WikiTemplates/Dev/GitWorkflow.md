# Git Workflow & Branching Strategy

Comprehensive guide to Git workflow, branching conventions, and commit best practices.

## Branching Strategy

We use **GitHub Flow** (simplified Git Flow) with protected main branch.

````````````
main (protected) ──────────────────────────────────────→
       ↓                          ↓
    feature/123-add-auth    bugfix/456-fix-crash
       ↓                          ↓
      [commits]                [commits]
       ↓                          ↓
      [PR + Review]           [PR + Review]
       ↓                          ↓
      merge →                 merge →
````````````

## Branch Naming Conventions

**Pattern**: \``<type>/<ticket-number>-<brief-description>\``

### Branch Types

| Type | Usage | Example |
|------|-------|---------|
| \``feature/\`` | New features | \``feature/123-add-user-authentication\`` |
| \``bugfix/\`` | Bug fixes | \``bugfix/456-fix-login-crash\`` |
| \``hotfix/\`` | Urgent production fixes | \``hotfix/789-security-patch\`` |
| \``refactor/\`` | Code refactoring | \``refactor/321-cleanup-api-layer\`` |
| \``docs/\`` | Documentation only | \``docs/234-update-api-guide\`` |
| \``test/\`` | Test improvements | \``test/567-add-integration-tests\`` |

### Rules

✅ **DO**:
- Always include ticket number: \``feature/123-...\``
- Use kebab-case: \``add-user-auth\`` not \``addUserAuth\``
- Be descriptive but concise (max 50 chars)
- Delete branch after merge

❌ **DON'T**:
- Use generic names: \``fix\``, \``update\``, \``temp\``
- Skip ticket number: \``feature/new-feature\``
- Use spaces or special characters

## Commit Message Conventions

### Format

````````````
<type>(<scope>): <subject>

[optional body]

[optional footer]
````````````

### Types

- \``feat\``: New feature
- \``fix\``: Bug fix
- \``docs\``: Documentation changes
- \``style\``: Code style changes (formatting, no logic change)
- \``refactor\``: Code refactoring
- \``test\``: Adding or updating tests
- \``chore\``: Build process, tooling, dependencies

### Examples

**Good**:
````````````
feat(auth): add JWT token validation

Implement JWT token validation middleware with expiry check.
Includes unit tests and error handling.

Closes #123
````````````

**Bad**:
````````````
updated code
````````````

### Rules

✅ **DO**:
- Use imperative mood: "add" not "added"
- Capitalize first letter
- No period at end of subject
- Link to work item: "Closes #123" or "Refs #456"
- Keep subject under 72 characters
- Explain "why" in body, not "what" (code shows "what")

❌ **DON'T**:
- Write vague messages: "fix bug", "update"
- Commit unrelated changes together
- Skip linking work items

## Daily Workflow

### 1. Start New Work

````````````bash
# Update main branch
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/123-add-user-auth

# Verify branch
git branch --show-current
````````````

### 2. Make Changes

````````````bash
# Make changes to files
code src/Auth/AuthService.cs

# Check status
git status

# Review changes
git diff

# Stage changes
git add src/Auth/AuthService.cs
# or stage all
git add .
````````````

### 3. Commit Changes

````````````bash
# Commit with message
git commit -m "feat(auth): add JWT validation middleware"

# Or open editor for detailed message
git commit
````````````

### 4. Push to Remote

````````````bash
# First push (set upstream)
git push -u origin feature/123-add-user-auth

# Subsequent pushes
git push
````````````

### 5. Keep Branch Updated

````````````bash
# Fetch latest main
git checkout main
git pull origin main

# Rebase your branch
git checkout feature/123-add-user-auth
git rebase main

# Or merge (if rebase causes issues)
git merge main

# Push updated branch (may need force-push after rebase)
git push --force-with-lease
````````````

### 6. Create Pull Request

1. Push your branch
2. Go to Azure Repos → Pull Requests
3. Click "New Pull Request"
4. Select: \``feature/123-add-user-auth\`` → \``main\``
5. Fill PR template
6. Link work item (required)
7. Add reviewers
8. Submit

### 7. Address Review Feedback

````````````bash
# Make requested changes
code src/Auth/AuthService.cs

# Commit changes
git add .
git commit -m "refactor(auth): address PR feedback - improve error handling"

# Push to update PR
git push
````````````

### 8. Merge and Cleanup

After PR approval:

````````````bash
# Merge via Azure DevOps UI (recommended)
# Or locally:
git checkout main
git pull origin main
git merge --no-ff feature/123-add-user-auth
git push origin main

# Delete branch
git branch -d feature/123-add-user-auth
git push origin --delete feature/123-add-user-auth
````````````

## Advanced Git Commands

### Fixing Mistakes

#### Undo Last Commit (keep changes)
````````````bash
git reset --soft HEAD~1
````````````

#### Undo Last Commit (discard changes)
````````````bash
git reset --hard HEAD~1
````````````

#### Amend Last Commit Message
````````````bash
git commit --amend -m "new message"
````````````

#### Undo Changes to File
````````````bash
git checkout -- filename.cs
````````````

### Interactive Rebase (Clean History)

````````````bash
# Rebase last 3 commits
git rebase -i HEAD~3

# Options:
# pick - keep commit
# squash - combine with previous
# edit - modify commit
# drop - remove commit
````````````

### Stash Changes (Temporary Save)

````````````bash
# Save current changes
git stash

# List stashes
git stash list

# Apply latest stash
git stash apply

# Apply and remove stash
git stash pop
````````````

### Cherry-Pick (Copy Commit)

````````````bash
# Copy commit to current branch
git cherry-pick <commit-hash>
````````````

## Conflict Resolution

### When Conflicts Occur

````````````bash
# Attempt merge/rebase
git merge main
# CONFLICT: Fix conflicts then continue

# View conflicted files
git status

# Open conflicted file - look for:
<<<<<<< HEAD
your changes
=======
incoming changes
>>>>>>> main

# Edit to resolve, remove markers

# Mark as resolved
git add filename.cs

# Complete merge
git commit
````````````

### Prevention

- Pull \``main\`` frequently
- Keep branches short-lived (< 3 days)
- Communicate with team about shared files

## Git Configuration

### Recommended Settings

````````````bash
# User identity
git config --global user.name "Your Name"
git config --global user.email "your.email@company.com"

# Default editor
git config --global core.editor "code --wait"

# Default branch name
git config --global init.defaultBranch main

# Auto-fix whitespace
git config --global apply.whitespace fix

# Better diff algorithm
git config --global diff.algorithm histogram

# Reuse recorded resolutions
git config --global rerere.enabled true
````````````

### Useful Aliases

````````````bash
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.ci commit
git config --global alias.st status
git config --global alias.last 'log -1 HEAD'
git config --global alias.unstage 'reset HEAD --'
````````````

## Best Practices Summary

1. ✅ **Commit early, commit often** - Small, logical commits
2. ✅ **Write meaningful messages** - Explain "why", not "what"
3. ✅ **One feature per branch** - Keep branches focused
4. ✅ **Keep branches up to date** - Pull main daily
5. ✅ **Review before pushing** - Use \``git diff\`` before commit
6. ✅ **Link work items** - Every commit references ticket
7. ✅ **Delete merged branches** - Keep repository clean
8. ✅ **Never commit secrets** - Use .gitignore and .env

---

**Next Steps**: Practice these workflows and see [Code Review Checklist](/Development/Code-Review-Checklist).

---

## 📚 References

- [Git Branching Strategies](https://learn.microsoft.com/en-us/azure/devops/repos/git/git-branching-guidance)
- [GitHub Flow](https://githubflow.github.io/)
- [Gitflow Workflow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Semantic Versioning](https://semver.org/)