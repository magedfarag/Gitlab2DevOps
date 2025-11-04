# Contributing to GitLab to Azure DevOps Migration Tool

Thank you for your interest in contributing! This project aims to provide a reliable, secure, and enterprise-ready migration solution for the community.

## 🤝 How to Contribute

### Reporting Issues

If you encounter bugs or have feature requests:

1. **Search existing issues** to avoid duplicates
2. **Create a new issue** with:
   - Clear, descriptive title
   - Detailed description of the problem/feature
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Environment details (PowerShell version, OS, Azure DevOps/GitLab versions)
   - Relevant log excerpts (sanitize sensitive data!)

### Submitting Pull Requests

1. **Fork the repository** and create a feature branch
   ```powershell
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following our standards:
   - Use clear, descriptive commit messages
   - Follow existing code style (4-space indentation, PascalCase for functions)
   - Add comments for complex logic
   - Keep functions focused and modular

3. **Test thoroughly**:
   - Test with both single and bulk migrations
   - Verify pre-flight validation works correctly
   - Check that logs are generated properly
   - Test with different Azure DevOps API versions (6.0, 7.0, 7.1)

4. **Update documentation**:
   - Update README.md if adding new features
   - Add examples for new parameters
   - Update troubleshooting section if relevant

5. **Submit your PR**:
   - Provide a clear description of changes
   - Reference any related issues
   - Explain the motivation and impact

## 🛡️ Security Guidelines

- **Never commit credentials** (PATs, tokens, passwords)
- **Never commit real organization data** (URLs, project names)
- Use generic examples (example.com, organization/project)
- Sanitize all log excerpts before sharing
- Report security vulnerabilities privately (don't open public issues)

## 📋 Code Style

- **PowerShell Best Practices**:
  - Use `Set-StrictMode -Version Latest`
  - Prefer splatting for complex parameters
  - Use `Write-Host` for user-facing messages
  - Use approved PowerShell verbs (Get, Set, New, Remove, etc.)
  
- **Function Naming**:
  - PascalCase with hyphen (e.g., `New-MigrationPreReport`)
  - Descriptive names that explain purpose
  
- **Error Handling**:
  - Use try-catch for REST API calls
  - Log errors with context
  - Provide actionable error messages

- **Comments**:
  - Explain "why", not "what"
  - Document non-obvious behavior
  - Use inline comments for complex logic

## 🧪 Testing Checklist

Before submitting a PR, verify:

- [ ] Pre-flight validation works and blocks invalid migrations
- [ ] Single project migration completes successfully
- [ ] Bulk migration processes multiple projects
- [ ] Logs are generated with proper timestamps
- [ ] Git credentials are cleaned up after operations
- [ ] REST API errors include status codes
- [ ] Script works with environment variables only
- [ ] Script validates required parameters at start
- [ ] Documentation matches new behavior

## 📝 Documentation Standards

- Use clear, concise language
- Provide code examples for new features
- Include expected output where relevant
- Update table of contents if adding new sections
- Use proper Markdown formatting
- Add troubleshooting entries for common issues

## 🎯 Priority Areas

We especially welcome contributions in:

- **Testing**: Unit tests, integration tests, automated validation
- **Performance**: Optimizations for large repositories or bulk migrations
- **Compatibility**: Support for additional Azure DevOps/GitLab versions
- **Features**: Additional branch policies, custom templates, reporting enhancements
- **Documentation**: Tutorials, video guides, translation to other languages
- **Bug Fixes**: Any issues reported in the issue tracker

## ❓ Questions?

- Review the [README.md](README.md) for usage documentation
- Check [Troubleshooting](README.md#troubleshooting) section
- Search existing issues for similar questions
- Open a new issue with the "question" label

## 📜 Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help create a welcoming environment for all contributors
- Assume good intentions

## 🏆 Recognition

All contributors will be recognized in our README. Significant contributions may be highlighted in release notes.

---

**Thank you for helping make this tool better for everyone! 🚀**
