# Prerequisites: 
#     - Install github cli (https://cli.github.com/)
#     - Your user needs to have write permissions to both orgs

param (
    [Parameter(Mandatory = $true, HelpMessage = "example: octo-1")]
    [string]
    $SourceOrg,
    [Parameter(Mandatory = $true, HelpMessage = "example: octo-1")]
    [int]
    $SourceProjectNumber,
    [Parameter(Mandatory = $true, HelpMessage = "example: 1")]
    [string]
    $TargetOrg,
    [Parameter(HelpMessage = "This limit is used when getting issues from the source projectboard - Set this to at least the number of issues you have in your board")]
    [int]
    $IssueLimit = 500,
    [switch]
    $SkipLogin,
    [switch]
    $SkipAuthScopeUpdate
)

$Script:STEPS = 6

$Script:stepCounter = 0

$Script:OverallProgressParameters = @{
    Activity         = "Migrating GitHub Project"
    Status           = "Running"
    CurrentOperation = "Starting"
    PercentComplete  = 0
}

$Script:DetailProgressParameters = @{
    Id               = 1
    Activity         = "Migrating GitHub Project"
    PercentComplete  = 0
    CurrentOperation = ""
    Completed        = $false
}

$ignoredFieldNames = @("Title", "Assignees", "Labels", "Linked pull requests", "Milestone", "Repository", "Reviewers")

function Update-OverallProgress {
    param(
        [string]
        $CurrentOperation
    )
    $Script:stepCounter += 1
    $Script:OverallProgressParameters.PercentComplete = $Script:stepCounter / $Script:STEPS * 100
    $Script:OverallProgressParameters.CurrentOperation = $CurrentOperation
    Write-Progress @Script:OverallProgressParameters
}

if (!$SkipLogin) {
    gh auth login -s project
} elseif (!$SkipAuthScopeUpdate) {
    gh auth refresh -s project
}

Read-Host "Make sure you have migrated the all repos that contain issues in this project to $TargetOrg - Press Enter to start migration"

Update-OverallProgress -CurrentOperation "Getting Source Project"
$sourceProject = gh project view $SourceProjectNumber --owner $SourceOrg --format json | ConvertFrom-Json
Update-OverallProgress -CurrentOperation "Copy Source Project"
$targetProject = gh project copy $SourceProjectNumber --source-owner $SourceOrg --target-owner $TargetOrg --drafts --title $sourceProject.title --format json | ConvertFrom-Json

Start-Sleep -Seconds 10

Update-OverallProgress -CurrentOperation "Getting Source Project Fields"
$targetFields = (gh project field-list $targetProject.number --owner $TargetOrg --format json | ConvertFrom-Json).fields
$targetFieldsDict = @{}
foreach ($field in $targetFields) {
    if ($ignoredFieldNames -notcontains $field.name) {
        $targetFieldsDict[$field.name] = $field
    }
}

Update-OverallProgress -CurrentOperation "Getting Source Project items"
# Get Items from current project
$sourceProjectItems = (gh project item-list $SourceProjectNumber --owner $SourceOrg --format json -L $IssueLimit | ConvertFrom-Json).items

$SourceTargetItemMapping = @{}
$itemMigrationCounter = 0
$Script:DetailProgressParameters.Activity = "Adding Items to Target Project"

Update-OverallProgress -CurrentOperation "Adding Items to Target Project"
# Add issues to new project
foreach ($sourceItem in $sourceProjectItems) {
    $itemMigrationCounter++
    $Script:DetailProgressParameters.PercentComplete = $itemMigrationCounter / $sourceProjectItems.Count * 100
    $Script:DetailProgressParameters.CurrentOperation = "Adding Item $($sourceItem.content.repository) ($itemMigrationCounter/$($sourceProjectItems.Count))"
    Write-Progress @Script:DetailProgressParameters

    if ($sourceItem.content.type -eq "DraftIssue") {
        continue;
    }

    $targetItem = gh project item-add $targetProject.number --owner $TargetOrg --url $sourceItem.content.url --format json | ConvertFrom-Json
    $SourceTargetItemMapping.Add($sourceItem.id, $targetItem.id)
    Start-Sleep -Seconds 1 # Documentation recommends a 1 second delay between cli commands
}

# Copy properties of source items to target items

$itemMigrationCounter = 0
$Script:DetailProgressParameters.Activity = "Adding Items to Target Project"

Update-OverallProgress -CurrentOperation "Cloning Itemproperties to Target Project"
foreach ($sourceItem in $sourceProjectItems) {
    $itemMigrationCounter++
    $Script:DetailProgressParameters.PercentComplete = $itemMigrationCounter / $sourceProjectItems.Count * 100
    $Script:DetailProgressParameters.CurrentOperation = "Adding Item $($sourceItem.content.repository) ($itemMigrationCounter/$($sourceProjectItems.Count))"
    Write-Progress @Script:DetailProgressParameters

    if (!$SourceTargetItemMapping.ContainsKey($sourceItem.id)) {
        continue;
    }

    $targetItemId = $SourceTargetItemMapping[$sourceItem.id]
    $fieldCopyCounter = 0
    foreach ($fieldName in $targetFieldsDict.Keys) {
        $fieldCopyCounter++
        Write-Progress -ParentId 1 -Id 2 -Activity "Copying Fields" -CurrentOperation "Copying Field $fieldName ($fieldCopyCounter/$($targetFields.Count))" -PercentComplete ($fieldCopyCounter / $targetFields.Count * 100)
        if ($null -eq $sourceItem."$fieldName") {
            continue
        }

        $fieldDefinition = $targetFieldsDict[$fieldName]
        $sourceValue = $sourceItem."$fieldName"

        switch ($fieldDefinition.type) {
            "ProjectV2Field" { 
                if ($sourceValue -is [double] -or $sourceValue -is [decimal] -or $sourceValue -is [single] -or $sourceValue -is [int16] -or $sourceValue -is [int32] -or $sourceValue -is [int64] -or $sourceValue -is [uint16] -or $sourceValue -is [uint32] -or $sourceValue -is [uint64]) {
                    gh project item-edit --id "$targetItemId" --field-id "$($fieldDefinition.id)" --project-id "$($targetProject.id)" --number $sourceValue
                } elseif ($sourceValue -is [string]) {
                    $date = $null
                    try {
                        $date = [datetime]::parseexact($sourceValue, "yyyy-MM-dd", $null)
                    } catch {
                        # Fall through
                    }

                    $isDate = $null -ne $date
                    if ($isDate) {
                        gh project item-edit --id "$targetItemId" --field-id "$($fieldDefinition.id)" --project-id "$($targetProject.id)" --date $sourceValue
                    } else {
                        gh project item-edit --id "$targetItemId" --field-id "$($fieldDefinition.id)" --project-id "$($targetProject.id)" --text $sourceValue
                    }

                } else {
                    Write-Warning "$($sourceValue.GetType().Name) is not supported for field $fieldName"
                    continue;
                }
                break;
            }
            "ProjectV2SingleSelectField" {
                $option = $fieldDefinition.options | Where-Object { $_.name -eq $sourceValue } | Select-Object -First 1

                if ($null -eq $option) {
                    Write-Warning "Option $sourceValue not found for field $fieldName"
                    continue;
                }

                gh project item-edit --id "$targetItemId" --field-id "$($fieldDefinition.id)" --project-id "$($targetProject.id)" --single-select-option-id "$($option.id)"
                break;
            }
            "ProjectV2IterationField" {
                Write-Warning "Iterations are not supported"
                continue;
            }
            default {
                Write-Warning "Field type $($fieldDefinition.type) is not supported"
                continue; 
            }
        }
        Start-Sleep -Seconds 1 # Documentation recommends a 1 second delay between cli commands
    }
}
