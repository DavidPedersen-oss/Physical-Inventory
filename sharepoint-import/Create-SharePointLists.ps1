<#
.SYNOPSIS
  Creates all five Beach Asset Management SharePoint lists (Assets, Departments,
  Users, AuditUpdates, ImportHistory) with the exact internal column names the
  Power Automate flows expect, then bulk-imports the CSV data in this folder.

.REQUIREMENTS
  - PowerShell 7+  (https://aka.ms/powershell)
  - PnP.PowerShell:  Install-Module PnP.PowerShell -Scope CurrentUser
  - An Entra ID app registration for PnP interactive sign-in. If your account is
    allowed to register apps, one command sets it up:
        Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "BeachProperty" -Tenant <tenant>.onmicrosoft.com
    It prints a ClientId - pass that below. If IT must register it for you, ask
    for a public-client app with delegated SharePoint "AllSites.FullControl".
  - If you can't get an app registered at all, fall back to the manual steps in
    the README (section 2) - the column layout below is the source of truth.

.EXAMPLE
  ./Create-SharePointLists.ps1 -SiteUrl "https://csulb.sharepoint.com/sites/PropertyManagement" -ClientId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
  # Create the lists only, skip the CSV data import:
  ./Create-SharePointLists.ps1 -SiteUrl "https://..." -ClientId "..." -SkipData
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [switch]$SkipData
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# List definitions. Name = internal name (frozen at creation - never change).
# Type Text = single line, Note = multiple lines (plain), Number = number.
# Title is created automatically on every list; TitleLabel just renames its
# display label (the internal name stays "Title", which is what the flows use).
# ---------------------------------------------------------------------------
$lists = @(
    @{
        Name = 'Assets'; TitleLabel = 'AssetID'
        Fields = @(
            @{ Name = 'TagNumber';   Type = 'Text' }
            @{ Name = 'Dept';        Type = 'Text' }
            @{ Name = 'DeptName';    Type = 'Text' }
            @{ Name = 'DivArea';     Type = 'Text' }
            @{ Name = 'Description'; Type = 'Note' }
            @{ Name = 'SerialID';    Type = 'Text' }
            @{ Name = 'Location';    Type = 'Text' }
            @{ Name = 'Custodian';   Type = 'Text' }
            @{ Name = 'Category';    Type = 'Text' }
            @{ Name = 'AcqDate';     Type = 'Text' }
            @{ Name = 'InServiceDt'; Type = 'Text' }
            @{ Name = 'PONo';        Type = 'Text' }
            @{ Name = 'SumAmount';   Type = 'Number' }
            @{ Name = 'Status';      Type = 'Text' }
            @{ Name = 'Notes';       Type = 'Note' }
            @{ Name = 'UpdatedBy';   Type = 'Text' }
            @{ Name = 'LastUpdated'; Type = 'Text' }
            @{ Name = 'EditHistory'; Type = 'Note' }
        )
        Csv = 'Assets.csv'
    }
    @{
        Name = 'Departments'; TitleLabel = 'DeptID'
        Fields = @(
            @{ Name = 'DeptName';  Type = 'Text' }
            @{ Name = 'DivArea';   Type = 'Text' }
            @{ Name = 'SortOrder'; Type = 'Number' }
            @{ Name = 'Completed'; Type = 'Text' }
            @{ Name = 'Phase';     Type = 'Text' }
        )
        Csv = 'Departments.csv'
    }
    @{
        Name = 'Users'; TitleLabel = 'Username'
        Fields = @(
            @{ Name = 'DisplayName';  Type = 'Text' }
            @{ Name = 'Role';         Type = 'Text' }
            @{ Name = 'Salt';         Type = 'Text' }
            @{ Name = 'PasswordHash'; Type = 'Text' }
            @{ Name = 'Active';       Type = 'Text' }
        )
        Csv = 'Users.csv'
    }
    @{
        Name = 'AuditUpdates'; TitleLabel = 'AssetID'
        Fields = @(
            @{ Name = 'Field';     Type = 'Text' }
            @{ Name = 'OldValue';  Type = 'Note' }
            @{ Name = 'NewValue';  Type = 'Note' }
            @{ Name = 'Status';    Type = 'Text' }
            @{ Name = 'Timestamp'; Type = 'Text' }
            @{ Name = 'User';      Type = 'Text' }
        )
        Csv = $null   # append-only log, starts empty
    }
    @{
        Name = 'ImportHistory'; TitleLabel = 'Timestamp'
        Fields = @(
            @{ Name = 'User';           Type = 'Text' }
            @{ Name = 'Filename';       Type = 'Text' }
            @{ Name = 'RowsMatched';    Type = 'Number' }
            @{ Name = 'RowsAdded';      Type = 'Number' }
            @{ Name = 'RowsConflicted'; Type = 'Number' }
            @{ Name = 'Summary';        Type = 'Note' }
        )
        Csv = $null   # append-only log, starts empty
    }
)

function New-FieldXml($field) {
    $name = $field.Name
    switch ($field.Type) {
        'Text'   { "<Field Type='Text' Name='$name' StaticName='$name' DisplayName='$name' MaxLength='255' />" }
        'Note'   { "<Field Type='Note' Name='$name' StaticName='$name' DisplayName='$name' RichText='FALSE' NumLines='6' />" }
        'Number' { "<Field Type='Number' Name='$name' StaticName='$name' DisplayName='$name' />" }
    }
}

Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $ClientId

foreach ($list in $lists) {
    $existing = Get-PnPList -Identity $list.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "List '$($list.Name)' already exists - leaving it as is, checking columns." -ForegroundColor Yellow
    }
    else {
        Write-Host "Creating list '$($list.Name)' ..." -ForegroundColor Cyan
        New-PnPList -Title $list.Name -Template GenericList -OnQuickLaunch | Out-Null
    }

    # Rename the Title column's display label (internal name stays Title)
    Set-PnPField -List $list.Name -Identity 'Title' -Values @{ Title = $list.TitleLabel }

    $currentFields = (Get-PnPField -List $list.Name).InternalName
    $view = Get-PnPView -List $list.Name -Identity 'All Items' -ErrorAction SilentlyContinue
    foreach ($field in $list.Fields) {
        if ($currentFields -contains $field.Name) {
            Write-Host "  column $($field.Name) already present" -ForegroundColor DarkGray
            continue
        }
        Add-PnPFieldFromXml -List $list.Name -FieldXml (New-FieldXml $field) | Out-Null
        Write-Host "  + $($field.Name) ($($field.Type))"
    }
    if ($view) {
        $wanted = @('Title') + ($list.Fields | ForEach-Object { $_.Name })
        Set-PnPView -List $list.Name -Identity $view.Id -Fields $wanted | Out-Null
    }
}

if (-not $SkipData) {
    foreach ($list in $lists) {
        if (-not $list.Csv) { continue }
        $csvPath = Join-Path $here $list.Csv
        if (-not (Test-Path $csvPath)) {
            Write-Host "Skipping data for '$($list.Name)' - $($list.Csv) not found next to this script." -ForegroundColor Yellow
            continue
        }
        $itemCount = (Get-PnPList -Identity $list.Name).ItemCount
        if ($itemCount -gt 0) {
            Write-Host "Skipping data for '$($list.Name)' - it already has $itemCount item(s)." -ForegroundColor Yellow
            continue
        }

        $rows = Import-Csv $csvPath
        Write-Host "Importing $($rows.Count) rows into '$($list.Name)' ..." -ForegroundColor Cyan
        $numberFields = ($list.Fields | Where-Object { $_.Type -eq 'Number' }).Name
        $batch = New-PnPBatch
        $inBatch = 0; $done = 0
        foreach ($row in $rows) {
            $values = @{}
            foreach ($prop in $row.PSObject.Properties) {
                if ($null -eq $prop.Value -or $prop.Value -eq '') { continue }
                if ($numberFields -contains $prop.Name) { $values[$prop.Name] = [double]$prop.Value }
                else { $values[$prop.Name] = [string]$prop.Value }
            }
            Add-PnPListItem -List $list.Name -Values $values -Batch $batch | Out-Null
            $inBatch++
            if ($inBatch -ge 100) {
                Invoke-PnPBatch -Batch $batch
                $done += $inBatch
                Write-Host "  $done / $($rows.Count)"
                $batch = New-PnPBatch; $inBatch = 0
            }
        }
        if ($inBatch -gt 0) {
            Invoke-PnPBatch -Batch $batch
            $done += $inBatch
        }
        Write-Host "  $done rows imported into '$($list.Name)'." -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'All done. Lists are ready - continue with README section 3 (the two Power Automate flows).' -ForegroundColor Green
