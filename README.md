# GitHub Projects Migration Tool

This little PowerShell script copies a project and adds all issues with all project field values to the copied Project.
## Limitations
- Issue fields
  - Iterations are not copied to the new project item
- Project
  - Project updates are not copied to the new Project

## Prerequisites
- PowerShell 5.1 or later
- [GitHub CLI](https://cli.github.com/) installed

## Usage
1. Download the `MigrateGitHubProject.ps1` file
2. Make sure it is unblocked & your [ExecutionPolicy allows the script to run](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.4).
3. Open a PowerShell shell in the folder where you saved the `MigrateGitHubProject.ps1` file
4. Make sure GitHub cli is installed. You can test this by typing and executing `gh --version` in your shell
5. Run the Script by calling `.\MigrateGitHubProject.ps1 [Parameters]`

### Parameters
|Parameter|Mandatory|Description|type|Example|
| ------- | ------- | --------- | -- | ----- |
|`-SourceOrg`|  <ul><li>[x] </li></ul> | GitHub Org, where the Project is located, that should be cloned | string | octo-org |
|`-SourceProjectNumber`|  <ul><li>[x] </li></ul> | GitHub Project number of the Project that should be cloned | int | 1 |
|`-TargetOrg`|  <ul><li>[x] </li></ul> | GitHub Org, where the Project should be cloned to| string | octi-org-2 |
|`-IssueLimit`|  <ul><li>[ ] </li></ul> | How many issues are getting migrated at a maximum. This should be more or equal the ammount of items that you have in the source GitHub project (default: 500) | int | 500 |
|`-SkipLogin`|  <ul><li>[ ] </li></ul> | Indicates if `gh auth login -s project` is skipped | switch |  |
|`-SkipAuthScopeUpdate`|  <ul><li>[ ] </li></ul> | Indicates if `gh auth refresh -s project` is skipped. This flag has only an effect if `-SkipLogin` is **not** provided | switch |  |
