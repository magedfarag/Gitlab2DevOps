# Documentation Extraction Feature

## Overview

**NEW in v2.1.0**: Automatic extraction of documentation files from GitLab repositories during the preparation phase.

## What It Does

During single or bulk preparation (Options 1 & 2), the tool automatically:

1. Scans all prepared GitLab project repositories
2. Finds documentation files with these extensions:
   - `.docx`, `.doc` (Word documents)
   - `.pdf` (PDF files)
   - `.xlsx`, `.xls` (Excel spreadsheets)
   - `.pptx`, `.ppt` (PowerPoint presentations)
3. Copies them to a centralized `docs/` folder at the Azure DevOps project level
4. Organizes files by repository name
5. Preserves the original folder structure within each repository
6. Provides extraction statistics

## Folder Structure

```
migrations/MyProject/
├── docs/                          # ← NEW: Centralized documentation folder
│   ├── frontend-app/              # Repository 1
│   │   ├── DesignMockups.pptx
│   │   └── specs/
│   │       └── UI-Requirements.docx
│   ├── backend-api/               # Repository 2
│   │   ├── API-Reference.pdf
│   │   └── docs/
│   │       └── Architecture.docx
│   └── documentation/             # Repository 3
│       ├── UserGuide.docx
│       ├── TechnicalSpec.pdf
│       └── guides/
│           ├── AdminGuide.docx
│           └── DeveloperGuide.pdf
├── frontend-app/
│   ├── repository/                # Original Git repository
│   └── reports/
├── backend-api/
│   ├── repository/
│   └── reports/
├── documentation/
│   ├── repository/
│   └── reports/
├── bulk-migration-config.json
├── reports/
└── logs/
```

## When It Runs

### Single Project Preparation (Option 1)
Automatically runs after successful GitLab project download:
```
[INFO] Preparing self-contained structure...
[SUCCESS] Project prepared: group/my-project

[INFO] Extracting documentation files...
[INFO] Found 3 repository directories to scan
[INFO] Scanning repository: my-project
  [INFO] Found 5 documentation files
    ✓ UserGuide.docx
    ✓ TechnicalSpec.pdf
    ✓ ProjectPlan.xlsx
    ✓ guides/AdminGuide.docx
    ✓ guides/DeveloperGuide.pdf

=== DOCUMENTATION EXTRACTION SUMMARY ===
Repositories scanned: 1
Total files extracted: 5
Total size: 2.4 MB

Files by type:
  .docx : 2 files
  .pdf : 2 files
  .xlsx : 1 files

Documentation folder: C:\Projects\migrations\MyProject\docs
```

### Bulk Preparation (Option 2)
Automatically runs after all projects are prepared:
```
[INFO] Bulk preparation completed:
       Successful: 3 / 3
       Duration: 2.5 minutes

[INFO] Extracting documentation files...
[INFO] Found 3 repository directories to scan
[INFO] Scanning repository: frontend-app
  [INFO] Found 1 documentation files
    ✓ DesignMockups.pptx
[INFO] Scanning repository: backend-api
  [INFO] Found 2 documentation files
    ✓ API-Reference.pdf
    ✓ docs\Architecture.docx
[INFO] Scanning repository: documentation
  [INFO] Found 6 documentation files
    ✓ UserGuide.docx
    ✓ TechnicalSpec.pdf
    ✓ ProjectPlan.xlsx
    ✓ guides/AdminGuide.docx
    ✓ guides/DeveloperGuide.pdf
    ✓ Presentation.pptx

=== DOCUMENTATION EXTRACTION SUMMARY ===
Repositories scanned: 3
Total files extracted: 9
Total size: 4.8 MB

Files by type:
  .docx : 3 files
  .pdf : 3 files
  .pptx : 2 files
  .xlsx : 1 files

Documentation folder: C:\Projects\migrations\ConsolidatedProject\docs
[SUCCESS] Extracted 9 documentation files (4.8 MB)
```

## Manual Extraction

You can also manually extract documentation from an already-prepared project:

```powershell
# Load the GitLab module
Import-Module .\modules\GitLab\GitLab.psm1

# Extract documentation
$stats = Export-GitLabDocumentation -AdoProject "MyProject"

# View statistics
$stats
```

### Custom File Extensions

If you need to extract additional file types:

```powershell
Export-GitLabDocumentation -AdoProject "MyProject" -DocExtensions @('docx', 'pdf', 'xlsx', 'pptx', 'md', 'txt', 'odt')
```

## Benefits

1. **Centralized Access**: All documentation in one easy-to-find location
2. **Repository Organization**: Files grouped by source repository
3. **Structure Preservation**: Original folder hierarchy maintained
4. **No Manual Work**: Fully automatic during preparation
5. **Easy Sharing**: Single docs/ folder can be zipped and shared with stakeholders
6. **Audit Trail**: Extraction statistics logged for reference

## What Happens to Original Files?

- Original files remain in the Git repositories (`repository/` folders)
- Documentation extraction only **copies** files, never moves or deletes
- The `docs/` folder is a convenience copy for easy access
- Git repositories are pushed to Azure DevOps with all original files intact

## Limitations

- Only extracts files from the working tree (checked out files)
- Does not extract from Git history or old commits
- Large binary files may increase migration folder size
- Only scans prepared repositories (must run Option 1 or 2 first)

## Statistics in Config File

For bulk migrations, extraction statistics are added to `bulk-migration-config.json`:

```json
{
  "preparation_summary": {
    "total_projects": 3,
    "successful_preparations": 3,
    "total_size_MB": 450,
    "documentation_extracted": 9,
    "documentation_size_MB": 4.8,
    ...
  }
}
```

## Troubleshooting

### No documentation files found
- Verify repositories were successfully cloned (check `repository/` folders)
- Confirm documentation files have supported extensions
- Check file permissions (read access required)

### Extraction failed with error
- Ensure sufficient disk space for copying files
- Verify write permissions to `migrations/` folder
- Check logs in `migrations/{Project}/logs/` for details

### Missing some expected files
- Some files may not be in the default branch
- Files in .gitignore are not cloned and won't be extracted
- Git LFS pointer files are extracted as text (not binary)

## See Also

- [Quick Start Guide](quickstart.md)
- [Bulk Migration Guide](guides/BULK_MIGRATION_CONFIG.md)
- [CLI Usage](cli-usage.md)
