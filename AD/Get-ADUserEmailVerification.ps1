<#
.SYNOPSIS
    Verifies if users exist in Active Directory and extracts their email addresses.

.DESCRIPTION
    This script offers two modes of operation:
    1. Single user verification - Check a single user and display results on screen
    2. Bulk verification - Process multiple users from a CSV file
    
    Both modes will verify if users exist in Active Directory and retrieve their email addresses.

.STEPS
    1. Select operation mode (single user or bulk CSV)
    2. Provide required input (username or CSV path)
    3. View results on screen or in output CSV file

.EXPECTED CSV HEADERS (for bulk mode)
    fullname - SamAccountName or identifier to search for in AD

.OUTPUT
    Single mode: Results displayed on screen
    Bulk mode: CSV file with FullName, Email, and ExistsInAD columns

.REQUIREMENTS
    - ActiveDirectory PowerShell module installed.
    - Read access to the specific AD OU.
    - Read/write permissions for CSV file paths (bulk mode).

.NOTES
    Author: Thomas Bonnet
    Version: 1.0
    Date: 2024-01-15

.EXAMPLE
    # Just run the script and follow the prompts
    .\Get-ADUserEmailVerification.ps1
#>

[CmdletBinding()]
param()

# Initialize
Begin {
    # Verify AD module is available
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        Write-Error "ActiveDirectory module not available. Please install RSAT or import the module."
        exit 1
    }
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-Error "Failed to import ActiveDirectory module: $_"
        exit 1
    }
    
    # Define OU for search
    $searchBase = "OU=XXX,DC=yourdomain,DC=com"  # Update this to your actual domain structure
    
    # Function to check a single user
    function Get-SingleUserInfo {
        param (
            [string]$Username
        )
        
        try {
            $adUser = Get-ADUser -Filter "SamAccountName -eq '$Username'" -SearchBase $searchBase -Properties EmailAddress -ErrorAction Stop
            
            if ($adUser) {
                $result = [PSCustomObject]@{
                    FullName = $Username
                    Email = $adUser.EmailAddress
                    ExistsInAD = $true
                }
                
                # Display the result in a formatted table
                $result | Format-Table -AutoSize
                
                # Option to export to CSV
                $exportOption = Read-Host "Do you want to export this result to CSV? (Y/N)"
                if ($exportOption.ToUpper() -eq "Y") {
                    $exportPath = Read-Host "Enter the export path (e.g., C:\Temp\result.csv)"
                    $result | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
                    Write-Host "Result exported to: $exportPath" -ForegroundColor Green
                }
            } else {
                Write-Host "User '$Username' not found in Active Directory." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "Error searching for user '$Username': $_" -ForegroundColor Red
        }
    }
    
    # Function to process CSV file
    function Process-BulkUsers {
        param (
            [string]$InputCSV
        )
        
        try {
            # Validate input file
            if (-not (Test-Path $InputCSV -PathType Leaf)) {
                Write-Host "Input file not found: $InputCSV" -ForegroundColor Red
                return
            }
            
            # Set default output path
            $OutputCSV = [System.IO.Path]::Combine(
                [System.IO.Path]::GetDirectoryName($InputCSV),
                [System.IO.Path]::GetFileNameWithoutExtension($InputCSV) + "_results" + [System.IO.Path]::GetExtension($InputCSV)
            )
            
            # Confirm output path
            $outputConfirm = Read-Host "Results will be saved to $OutputCSV. Continue? (Y/N)"
            if ($outputConfirm.ToUpper() -ne "Y") {
                $OutputCSV = Read-Host "Enter the desired output path"
            }
            
            # Create results array
            $results = [System.Collections.ArrayList]::new()
            
            # Read the CSV file
            $data = Import-Csv -Path $InputCSV -ErrorAction Stop
            
            # Check for the required column
            if (-not ($data | Get-Member -Name "fullname")) {
                Write-Host "The CSV file must contain a 'fullname' column." -ForegroundColor Red
                return
            }
            
            Write-Host "Processing $($data.Count) users..."
            $counter = 0
            
            # Process each user
            foreach ($user in $data) {
                $counter++
                $fullname = $user.fullname
                
                # Progress indicator
                if ($counter % 10 -eq 0) {
                    Write-Progress -Activity "Checking AD users" -Status "$counter of $($data.Count) processed" -PercentComplete (($counter / $data.Count) * 100)
                }
                
                try {
                    $adUser = Get-ADUser -Filter "SamAccountName -eq '$fullname'" -SearchBase $searchBase -Properties EmailAddress -ErrorAction Stop
                    
                    if ($adUser) {
                        [void]$results.Add([PSCustomObject]@{
                            FullName = $fullname
                            Email = $adUser.EmailAddress
                            ExistsInAD = $true
                        })
                    } else {
                        [void]$results.Add([PSCustomObject]@{
                            FullName = $fullname
                            Email = $null
                            ExistsInAD = $false
                        })
                    }
                } catch {
                    [void]$results.Add([PSCustomObject]@{
                        FullName = $fullname
                        Email = $null
                        ExistsInAD = $false
                        Error = $_.Exception.Message
                    })
                }
            }
            
            # Clear progress bar
            Write-Progress -Activity "Checking AD users" -Completed
            
            # Export results
            $results | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8
            
            # Display summary
            Write-Host "Results exported to: $OutputCSV" -ForegroundColor Green
            Write-Host "Total users processed: $($results.Count)"
            Write-Host "Users found in AD: $($results | Where-Object { $_.ExistsInAD -eq $true } | Measure-Object | Select-Object -ExpandProperty Count)"
            Write-Host "Users not found in AD: $($results | Where-Object { $_.ExistsInAD -eq $false } | Measure-Object | Select-Object -ExpandProperty Count)"
            
            # Option to display preview
            $previewOption = Read-Host "Do you want to see a preview of the results? (Y/N)"
            if ($previewOption.ToUpper() -eq "Y") {
                $results | Select-Object -First 10 | Format-Table -AutoSize
                if ($results.Count -gt 10) {
                    Write-Host "... and $($results.Count - 10) more rows" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "Error processing CSV file: $_" -ForegroundColor Red
        }
    }
}

# Main processing
Process {
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "      Active Directory User Email Verification Tool      " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Select operation mode:" -ForegroundColor Yellow
    Write-Host "1. Verify a single user" -ForegroundColor White
    Write-Host "2. Process multiple users from CSV file" -ForegroundColor White
    Write-Host ""
    
    do {
        $choice = Read-Host "Enter your choice (1 or 2)"
    } while ($choice -notin @("1", "2"))
    
    switch ($choice) {
        "1" {
            Write-Host "Single User Verification Mode" -ForegroundColor Green
            $username = Read-Host "Enter username (SamAccountName)"
            Get-SingleUserInfo -Username $username
        }
        "2" {
            Write-Host "Bulk CSV Processing Mode" -ForegroundColor Green
            
            # File selection options
            Write-Host "Select how to provide the CSV file:" -ForegroundColor Yellow
            Write-Host "1. Enter file path manually" -ForegroundColor White
            Write-Host "2. Use file selection dialog" -ForegroundColor White
            
            do {
                $fileChoice = Read-Host "Enter your choice (1 or 2)"
            } while ($fileChoice -notin @("1", "2"))
            
            if ($fileChoice -eq "1") {
                $csvPath = Read-Host "Enter the full path to your CSV file"
            } else {
                # Use file dialog
                Add-Type -AssemblyName System.Windows.Forms
                $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
                $fileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
                $fileDialog.Title = "Select CSV File with User Data"
                
                if ($fileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $csvPath = $fileDialog.FileName
                    Write-Host "Selected file: $csvPath" -ForegroundColor Green
                } else {
                    Write-Host "No file selected. Operation cancelled." -ForegroundColor Red
                    return
                }
            }
            
            Process-BulkUsers -InputCSV $csvPath
        }
    }
}

# End
End {
    Write-Host ""
    Write-Host "Operation completed." -ForegroundColor Cyan
}
