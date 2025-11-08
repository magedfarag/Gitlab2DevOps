# Contributing to Gitlab2DevOps

Thank you for considering contributing to Gitlab2DevOps! This document provides guidelines and instructions for contributing to the project.

---

## 🎯 Code of Conduct

By participating in this project, you agree to maintain a respectful, inclusive, and collaborative environment. We expect all contributors to:

- Be respectful and considerate
- Welcome newcomers and help them get started
- Focus on constructive feedback
- Accept responsibility and learn from mistakes
- Put the community's interests first

---

## 🚀 Quick Start for Contributors

### Prerequisites

- PowerShell 5.1+ or PowerShell Core 7+
- Git 2.20+
- GitHub account
- Familiarity with Azure DevOps and GitLab APIs (helpful but not required)

### Setup Development Environment

```powershell
# Fork and clone the repository
git clone https://github.com/YOUR-USERNAME/Gitlab2DevOps.git
cd Gitlab2DevOps

# Create a feature branch
git checkout -b feature/your-feature-name

# Set up environment variables
Copy-Item .env.example .env
# Edit .env with your test credentials

# Run tests to ensure everything works
Invoke-Pester -Path '.\tests' -Output Detailed
```

---

## 📝 How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates.

**When reporting a bug, include:**
- Clear, descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- PowerShell version (`$PSVersionTable.PSVersion`)
- Git version (`git --version`)
- Operating system
- Relevant log excerpts (from `logs/` directory)
- Error messages (sanitized to remove credentials)

**Bug Report Template:**
```markdown
### Description
[Clear description of the bug]

### Steps to Reproduce
1. Step one
2. Step two
3. Step three

### Expected Behavior
[What should happen]

### Actual Behavior
[What actually happens]

### Environment
- PowerShell Version: X.X.X
- Git Version: X.X.X
- OS: Windows/Linux/macOS
- Azure DevOps: Cloud/On-Premise

### Logs
[Paste relevant log excerpts here]
```

### Suggesting Features

Feature requests are welcome! Please provide:
- Clear use case and problem statement
- Proposed solution or implementation idea
- Examples of similar features in other tools
- Any potential challenges or considerations

### Submitting Pull Requests

1. **Fork the repository** and create a feature branch
2. **Make your changes** following our coding standards
3. **Add or update tests** for your changes
4. **Update documentation** if needed
5. **Run the test suite** and ensure all tests pass
6. **Commit with conventional commit messages**
7. **Push to your fork** and submit a pull request

**PR Checklist:**
- [ ] Tests pass (`Invoke-Pester -Path '.\tests' -Output Detailed`)
- [ ] Code follows PowerShell best practices
- [ ] Documentation updated (README, inline comments, etc.)
- [ ] Commit messages follow conventional commits
- [ ] PR description clearly explains changes
- [ ] No credentials or sensitive data in code

---

## 💻 Coding Standards

### PowerShell Best Practices

#### 1. Use Approved Verbs

```powershell
# ✅ GOOD - Approved verb
function Get-AdoProject { }
function New-AdoRepository { }
function Measure-AdoProject { }

# ❌ BAD - Unapproved verb
function Ensure-AdoProject { }
function Create-AdoRepository { }
```

#### 2. PascalCase Naming

```powershell
# ✅ GOOD
function Get-MigrationStatus {
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
}

# ❌ BAD
function get-migration_status {
    param([string]$project_name)
}
```

#### 3. Proper Parameter Attributes

```powershell
# ✅ GOOD
function Start-Migration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$ProjectName,
        
        [Parameter()]
        [ValidateSet('Migrate', 'Preview', 'Rollback')]
        [string]$Mode = 'Migrate',
        
        [switch]$Force
    )
}
```

#### 4. Error Handling

```powershell
# ✅ GOOD
try {
    $result = Invoke-RestMethod -Uri $uri -Headers $headers
    return $result
}
catch {
    Write-Error "Failed to retrieve project: $_"
    throw
}

# ❌ BAD
$result = Invoke-RestMethod -Uri $uri -Headers $headers
# No error handling
```

#### 5. Comment-Based Help

```powershell
<#
.SYNOPSIS
    Brief description of the function.

.DESCRIPTION
    Detailed description of what the function does.

.PARAMETER ProjectName
    Name of the Azure DevOps project.

.EXAMPLE
    Get-AdoProject -ProjectName "MyProject"
    
    Retrieves the specified Azure DevOps project.

.NOTES
    Requires ADO_PAT environment variable.
#>
function Get-AdoProject { }
```

### Module Organization

- **One function per logical operation**
- **Export only public functions** (use `Export-ModuleMember`)
- **Keep modules focused** (single responsibility principle)
- **Use sub-modules** for complex functionality

### Code Style

```powershell
# Indentation: 4 spaces (not tabs)
# Line length: Max 120 characters (soft limit)
# Braces: Opening brace on same line, closing brace on new line

function Get-AdoProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectName
    )
    
    # Use descriptive variable names
    $encodedName = [uri]::EscapeDataString($ProjectName)
    $apiUrl = "/_apis/projects/$encodedName"
    
    # Use meaningful comments for complex logic
    try {
        # Retrieve project with API version 7.0
        $project = Invoke-AdoRest GET $apiUrl -ApiVersion "7.0"
        return $project
    }
    catch {
        Write-Error "Failed to retrieve project '$ProjectName': $_"
        throw
    }
}
```

---

## 🧪 Testing Guidelines

### Test Structure

```powershell
Describe "Module: Get-AdoProject" {
    Context "When project exists" {
        It "Returns project object" {
            # Arrange
            Mock Invoke-AdoRest { return @{ name = "TestProject" } }
            
            # Act
            $result = Get-AdoProject -ProjectName "TestProject"
            
            # Assert
            $result.name | Should -Be "TestProject"
        }
    }
    
    Context "When project does not exist" {
        It "Throws error" {
            # Arrange
            Mock Invoke-AdoRest { throw "Not found" }
            
            # Act & Assert
            { Get-AdoProject -ProjectName "Missing" } | Should -Throw
        }
    }
}
```

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path '.\tests' -Output Detailed

# Run specific test file
Invoke-Pester -Path '.\tests\OfflineTests.ps1' -Output Detailed

# Run with coverage
Invoke-Pester -Configuration @{
    Run = @{ Path = '.\tests\*.Tests.ps1' }
    CodeCoverage = @{ 
        Enabled = $true
        Path = '.\modules\*.psm1'
        OutputFormat = 'JaCoCo'
    }
}
```

### Test Requirements

- ✅ All new functions must have tests
- ✅ Tests must not require API credentials
- ✅ Use mocks for external dependencies
- ✅ Test both success and failure scenarios
- ✅ Test edge cases (null values, empty strings, etc.)

---

## 📚 Documentation Standards

### Inline Documentation

- **Every function** must have comment-based help
- **Complex logic** must have explanatory comments
- **Parameters** must be documented clearly
- **Examples** must be practical and tested

### Markdown Documentation

- Use clear, concise language
- Include code examples
- Add screenshots where helpful
- Keep formatting consistent
- Update table of contents

### Documentation Files

- **README.md**: Overview, quick start, features
- **CHANGELOG.md**: Version history, breaking changes
- **CONTRIBUTING.md**: This file
- **docs/**: Detailed guides and references

---

## 🔄 Git Workflow

### Branching Strategy

```
main (production-ready code)
└── feature/your-feature     (new features)
└── fix/bug-description      (bug fixes)
└── docs/documentation-update (documentation)
└── refactor/code-improvement (refactoring)
```

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(migration): add support for Git LFS object transfer

- Implement LFS object detection
- Add automatic LFS transfer during migration
- Update documentation with LFS requirements

Closes #123

---

fix(security): prevent token leakage in logs

Token masking was not applied to error messages.
This fix ensures all tokens are masked before logging.

BREAKING CHANGE: Log format changed for security events

---

docs(readme): update installation instructions

Added prerequisites section and troubleshooting guide.
```

### Pull Request Process

1. **Update documentation** for any user-facing changes
2. **Add tests** for new functionality
3. **Update CHANGELOG.md** with your changes
4. **Ensure all tests pass** before requesting review
5. **Request review** from maintainers
6. **Address feedback** and update PR
7. **Squash commits** if requested

---

## 🏗️ Architecture Guidelines

### Module Design

- **Separation of concerns**: Each module has single responsibility
- **Loose coupling**: Modules minimize dependencies
- **High cohesion**: Related functions grouped together
- **Clear interfaces**: Public functions well-documented

### Adapter Pattern

```powershell
# GitLab adapter - no Azure DevOps knowledge
module GitLab {
    function Get-GitLabProject { }
    function Get-GitLabRepository { }
}

# Azure DevOps adapter - no GitLab knowledge
module AzureDevOps {
    function Get-AdoProject { }
    function New-AdoRepository { }
}

# Migration orchestrator - coordinates adapters
module Migration {
    function Start-Migration {
        $glProject = Get-GitLabProject
        $adoProject = Get-AdoProject
        # Orchestrate migration
    }
}
```

### Error Handling Strategy

1. **Catch specific exceptions** when possible
2. **Provide context** in error messages
3. **Use Write-Error** for recoverable errors
4. **Use throw** for unrecoverable errors
5. **Clean up resources** in finally blocks

---

## 🔍 Review Checklist

Before submitting your PR, verify:

### Code Quality
- [ ] Follows PowerShell best practices
- [ ] Uses approved verbs
- [ ] Proper error handling
- [ ] No hardcoded credentials
- [ ] Token masking in place
- [ ] Code is properly commented

### Testing
- [ ] All tests pass
- [ ] New tests added for new code
- [ ] Edge cases covered
- [ ] No flaky tests

### Documentation
- [ ] README updated if needed
- [ ] CHANGELOG.md updated
- [ ] Function help updated
- [ ] Examples included

### Git
- [ ] Conventional commit messages
- [ ] PR description is clear
- [ ] Branch is up to date with main
- [ ] No merge conflicts

---

## 📞 Getting Help

- **Documentation**: Check [docs/](docs/) directory
- **Issues**: Search [existing issues](https://github.com/magedfarag/Gitlab2DevOps/issues)
- **Discussions**: Start a [GitHub Discussion](https://github.com/magedfarag/Gitlab2DevOps/discussions)
- **Email**: Contact maintainers (see README)

---

## 🎉 Recognition

Contributors will be recognized in:
- **README.md**: Contributors section
- **Release notes**: Credit for features/fixes
- **CHANGELOG.md**: Attribution for changes

---

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

<div align="center">

**Thank you for contributing to Gitlab2DevOps!**

Your contributions help make migrations smoother for everyone.

</div>
