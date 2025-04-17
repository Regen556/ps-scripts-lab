<#
.SYNOPSIS
    Bulk update AD user expiration dates based on a CSV input.

.DESCRIPTION
    This script allows administrators to extend the expiration date of multiple Active Directory user accounts.
    It uses a CSV file as input, which must follow a specific format and be located under C:\Temp.
    Only enabled accounts (Disabled = False) will have their expiration date updated.

.PARAMETER CSV
    You will be prompted to select a CSV file containing users and attributes.

.EXPECTED CSV HEADERS
    Name | EmailAddress | Disabled | ExpirationDate
    - The headers are case-sensitive.
    - "Disabled" must be either True or False.
    - "ExpirationDate" must be with dd/MM/yyyy format

.STEPS
    1. A File Explorer prompt allows you to select your CSV file.
    2. The script will validate headers and content.
    3. The script updates the expiration date of each enabled user account in AD.

.REQUIREMENTS
    - Run as Administrator.
    - ActiveDirectory PowerShell module installed.
    - Access to modify user accounts in AD.

.NOTES
    Author: Thomas Bonnet
    Version: 1.0
    Date: 2025-04-17

.EXAMPLE
    # Launch the script manually
    .\AD-ExpirationDateExtention.ps1

#>

## INTRO
Write-Host "=== Active Directory Expiration Date Updater ===" -ForegroundColor Cyan

Write-Host "`nRequired:" -ForegroundColor Yellow
Write-Host "• CSV file must contain (case-sensitive): Name | EmailAddress | Disabled | ExpirationDate" -ForegroundColor White
Write-Host "• Best practice: store the CSV in an easy-to-access folder like C:\Temp" -ForegroundColor DarkCyan
Write-Host "• Script must be run as Administrator" -ForegroundColor Cyan
Write-Host "• Invalid format will cause errors" -ForegroundColor Red

Write-Host "`nSteps:" -ForegroundColor Yellow
Write-Host "1. Select the CSV file in the popup window" -ForegroundColor Cyan
Write-Host "2. Only active users (Disabled = False) will be updated" -ForegroundColor Cyan

Write-Host "`nEnsure all requirements are met before proceeding." -ForegroundColor Yellow

Write-Host "`nPress Enter to continue..." -ForegroundColor Green
Read-Host | Out-Null


# Load Windows Forms for file selection
Add-Type -AssemblyName System.Windows.Forms

# Open File Explorer to let the user choose the CSV file
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Title = "Select CSV File"
$openFileDialog.Filter = "CSV Files (*.csv)|*.csv"

if ($openFileDialog.ShowDialog() -eq "OK") {
    $csvFilePath = $openFileDialog.FileName
    Write-Output "Selected file: $csvFilePath"
} else {
    Write-Error "No file selected. Script terminated."
    exit
}

# Import CSV
try {
    $users = Import-Csv -Path $csvFilePath
} catch {
    Write-Host "Failed to import the CSV file. Check the format and try again." -ForegroundColor Red
    exit
}

# Process each user
$modifiedAccounts = @()

foreach ($user in $users) {
    $name = $user.Name
    $email = $user.EmailAddress
    $disabled = $user.Disabled
    $dateStr = $user.ExpirationDate

    # Validate the date format
    if (-not [DateTime]::TryParseExact($dateStr, 'dd/MM/yyyy', $null, 'None', [ref]$expDate)) {
        Write-Host "Invalid date format for $name. Skipping." -ForegroundColor Yellow
        continue
    }

    try {
        $adUser = Get-ADUser -Filter {EmailAddress -eq $email} -Properties AccountExpirationDate, Enabled

        if ($adUser -and $disabled -eq "False" -and $adUser.Enabled) {
            if ($adUser.AccountExpirationDate -ne $expDate) {
                # Update expiration date
                Set-ADUser $adUser -AccountExpirationDate $expDate
                Write-Host "$name updated with expiration date: $dateStr" -ForegroundColor Green

                # Add to modified list
                $modifiedAccounts += [PSCustomObject]@{
                    Name          = $name
                    Email         = $email
                    OldExpiration = $adUser.AccountExpirationDate
                    NewExpiration = $expDate
                    Status        = "Updated"
                }
            } else {
                Write-Host "$name already has this expiration date. Skipping." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "$name is either disabled or not found. Skipped." -ForegroundColor DarkYellow
        }
    } catch {
        Write-Host "Error processing $name : $_" -ForegroundColor Red
    }
}

# Display summary
if ($modifiedAccounts.Count -gt 0) {
    Write-Host "`nSummary of updated accounts:" -ForegroundColor Yellow
    $modifiedAccounts | Format-Table -AutoSize
} else {
    Write-Host "`nNo accounts were updated." -ForegroundColor Cyan
}
