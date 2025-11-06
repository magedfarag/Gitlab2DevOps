# Dependencies & Third-Party Libraries

Comprehensive guide to managing project dependencies and third-party libraries.

## Overview

This project uses several third-party libraries and frameworks. Understanding these dependencies is crucial for development, security, and maintenance.

## Dependency Management

### Package Managers

**For .NET Projects**:
- **NuGet**: Primary package manager
- Config: \``*.csproj\`` files and \``NuGet.config\``
- Restore: \``dotnet restore\``

**For Node.js Projects**:
- **npm** or **yarn**: JavaScript package managers
- Config: \``package.json\`` and \``package-lock.json\``
- Install: \``npm install\`` or \``yarn install\``

**For Python Projects**:
- **pip**: Python package manager
- Config: \``requirements.txt\`` or \``pyproject.toml\``
- Install: \``pip install -r requirements.txt\``

### Version Pinning Strategy

**Semantic Versioning**: \``MAJOR.MINOR.PATCH\``

| Symbol | Meaning | Example | Allows |
|--------|---------|---------|--------|
| \``^\`` | Compatible | \``^1.2.3\`` | 1.2.3 to < 2.0.0 |
| \``~\`` | Patch-level | \``~1.2.3\`` | 1.2.3 to < 1.3.0 |
| None | Exact | \``1.2.3\`` | Exactly 1.2.3 |
| \``*\`` | Any | \``*\`` | Any version (⚠️ not recommended) |

**Our Policy**:
- **Production Dependencies**: Pin exact versions or use \``~\`` for patches
- **Development Dependencies**: Can use \``^\`` for flexibility
- **Security Updates**: Apply immediately after testing

## Core Dependencies

### Runtime Dependencies

#### .NET Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| Microsoft.AspNetCore.App | 8.0.x | Web framework | MIT |
| Microsoft.EntityFrameworkCore | 8.0.x | ORM | MIT |
| Newtonsoft.Json | 13.0.3 | JSON serialization | MIT |
| Serilog.AspNetCore | 8.0.x | Logging | Apache 2.0 |
| AutoMapper | 12.0.x | Object mapping | MIT |

#### Node.js Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| express | ^4.18.0 | Web framework | MIT |
| axios | ^1.6.0 | HTTP client | MIT |
| lodash | ^4.17.21 | Utility functions | MIT |
| dotenv | ^16.3.0 | Environment config | BSD-2-Clause |

#### Python Projects

| Package | Version | Purpose | License |
|---------|---------|---------|---------|
| fastapi | ^0.104.0 | Web framework | MIT |
| sqlalchemy | ^2.0.0 | ORM | MIT |
| pydantic | ^2.5.0 | Data validation | MIT |
| requests | ^2.31.0 | HTTP client | Apache 2.0 |

### Development Dependencies

| Package | Purpose |
|---------|---------|
| xunit/jest/pytest | Unit testing |
| Moq/sinon/pytest-mock | Mocking |
| FluentAssertions | Test assertions |
| Faker/bogus | Test data generation |
| ESLint/Ruff | Linting |

## Adding New Dependencies

### Before Adding a Dependency

**Ask**:
1. ✅ **Is it necessary?** - Can we implement it ourselves simply?
2. ✅ **Is it maintained?** - Recent commits, active issues?
3. ✅ **Is it secure?** - Known vulnerabilities?
4. ✅ **Is the license compatible?** - Check license restrictions
5. ✅ **Is it the right tool?** - Better alternatives?
6. ✅ **What's the bundle size?** - For frontend dependencies

### Approval Process

**For New Dependencies**:
1. Create work item describing need
2. Research alternatives (document in ADR)
3. Get approval from tech lead
4. Add dependency
5. Update this documentation
6. Update license compliance doc

### Installation

**.NET**:
````````````bash
dotnet add package PackageName --version 1.2.3
````````````

**Node.js**:
````````````bash
npm install package-name@1.2.3 --save
# or for dev dependency
npm install package-name@1.2.3 --save-dev
````````````

**Python**:
````````````bash
pip install package-name==1.2.3
pip freeze > requirements.txt  # Update requirements
````````````

## Updating Dependencies

### Regular Updates

**Schedule**: Check for updates monthly

**Process**:
1. Check for outdated packages
2. Review changelogs
3. Test in development
4. Update documentation
5. Create PR with updates

### Commands

**.NET**:
````````````bash
# Check outdated
dotnet list package --outdated

# Update package
dotnet add package PackageName
````````````

**Node.js**:
````````````bash
# Check outdated
npm outdated

# Update specific package
npm update package-name

# Interactive updater (recommended)
npx npm-check-updates -i
````````````

**Python**:
````````````bash
# Check outdated
pip list --outdated

# Update package
pip install --upgrade package-name
````````````

### Security Updates

**Priority**: Apply within 48 hours for high/critical

**Check for Vulnerabilities**:

**.NET**:
````````````bash
dotnet list package --vulnerable
````````````

**Node.js**:
````````````bash
npm audit
npm audit fix
````````````

**Python**:
````````````bash
pip-audit
# or
safety check
````````````

### Breaking Changes

**When Major Version Updates**:
1. Read migration guide
2. Create feature branch
3. Update code for breaking changes
4. Run full test suite
5. Test manually
6. Document changes in commit message

## Dependency Security

### Best Practices

✅ **DO**:
- Keep dependencies updated
- Review security advisories
- Use dependency scanning tools
- Lock versions in production
- Audit new dependencies before adding
- Remove unused dependencies

❌ **DON'T**:
- Use dependencies with known vulnerabilities
- Add dependencies without review
- Use wildcards in production (\``*\``)
- Install packages globally that should be project-local

### Security Scanning

**Automated Scans**:
- GitHub Dependabot
- Snyk
- npm audit / dotnet list package --vulnerable
- OWASP Dependency-Check

**Manual Review**:
- Check CVE databases
- Review library GitHub issues
- Search for "CVE-YYYY-NNNNN" + package name

## License Compliance

### Allowed Licenses

✅ **Permissive** (generally okay):
- MIT
- Apache 2.0
- BSD (2-clause, 3-clause)
- ISC

⚠️ **Copyleft** (requires review):
- GPL (v2, v3)
- LGPL
- AGPL

❌ **Restricted** (not allowed):
- Proprietary without license
- "All Rights Reserved"

### Checking Licenses

**.NET**:
````````````bash
dotnet list package --include-transitive
# Check PackageProjectUrl for license
````````````

**Node.js**:
````````````bash
npx license-checker --summary
````````````

**Python**:
````````````bash
pip-licenses
````````````

## Common Dependencies Explained

### Logging: Serilog/Winston/Python logging

**Purpose**: Structured logging  
**Why**: Better than console.log, searchable, filterable  
**Usage**:
````````````csharp
_logger.LogInformation("User {UserId} logged in", userId);
````````````

### ORM: Entity Framework Core/TypeORM/SQLAlchemy

**Purpose**: Database abstraction  
**Why**: Type-safe queries, migrations, prevents SQL injection  
**Usage**:
````````````csharp
var users = await context.Users
    .Where(u => u.IsActive)
    .ToListAsync();
````````````

### Testing: xUnit/Jest/pytest

**Purpose**: Unit testing framework  
**Why**: Automated testing, regression prevention  
**Usage**:
````````````csharp
[Fact]
public void Should_Return_User_When_Valid_Id()
{
    // Arrange, Act, Assert
}
````````````

### HTTP Client: HttpClient/Axios/Requests

**Purpose**: Make HTTP requests  
**Why**: Interact with external APIs  
**Usage**:
````````````javascript
const response = await axios.get('/api/users');
````````````

## Troubleshooting Dependency Issues

### Issue: Package Not Found

**Solution**:
1. Check package name spelling
2. Clear package cache
3. Check package source/registry
4. Verify network connectivity

### Issue: Version Conflict

**Solution**:
````````````bash
# .NET
dotnet restore --force

# Node.js
rm package-lock.json
npm install

# Python
pip install --force-reinstall package-name
````````````

### Issue: Transitive Dependency Vulnerability

**Solution**:
- Update parent package
- Use dependency override/resolution
- Contact maintainer if not fixed

## Resources

- **NuGet Gallery**: https://www.nuget.org/
- **npm Registry**: https://www.npmjs.com/
- **PyPI**: https://pypi.org/
- **Snyk Vulnerability DB**: https://snyk.io/vuln
- **Common Vulnerabilities**: https://cve.mitre.org/

---

**Next Steps**: Keep dependencies updated monthly and check security advisories weekly.