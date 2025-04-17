<#
.SYNOPSIS
    Extracts users with access to specified network folders via Active Directory security groups.

.DESCRIPTION
    This script identifies all users who have access to specific network folders through Active Directory security groups.
    It processes a CSV file containing network paths, extracts the security groups from each path's ACL,
    and then retrieves all users who are members of those groups.
    
    The script maps the L: drive to the DFS root to ensure proper path resolution.

.PARAMETER CSV
    You will be prompted to select a CSV file containing network paths.

.EXPECTED CSV HEADERS
    NetworkPath
    - The header is case-sensitive.
    - Use full network paths (e.g., \\yourDomain\dfsroot\folder).

.ACTIONS
    To properly use the script, you need to modify several lines to add your domain
      Line 60, 69, 70, 233, 246

.STEPS
    1. A File Explorer prompt allows you to select your CSV file.
    2. The script validates the paths and tests their accessibility.
    3. For each valid path, the script retrieves security groups from the ACL.
    4. For each security group, members are recursively listed.
    5. Results are exported to C:\Temp\NetworkPathUsersOutput.csv.

.OUTPUT
    The script generates a CSV file with the following columns:
    - NetworkPath: The folder path analyzed
    - GroupName: The security group providing access
    - UserName: The user with access through the group
    - SecurityGroupManager: The manager of the security group

.REQUIREMENTS
    - Run as Administrator.
    - ActiveDirectory PowerShell module installed.
    - Network access to the specified file shares.
    - Write access to C:\Temp for the output file.

.NOTES
    Author: Thomas Bonnet
    Version: 1.1
    Date: 20-01-2025

.EXAMPLE
    # Launch the script manually
    .\AD-NetworkFoldersUserExtraction.ps1
#>

[CmdletBinding()]
param()

# Initialize variables and settings
Begin {
    # Constants that could be parameterized in future versions
    $DFSRoot = "\\YourDomain\dfsroot"
    $DriveLetter = "L"
    $ExportPath = "C:\Temp\NetworkPathUsersOutput.csv"
    
    # Create a hashtable for excluded groups (faster lookups)
    $ExcludedGroups = @{
        "SYSTEM" = $true
        "Administrators" = $true
        "Domain Admins" = $true
        "Enterprise Admins" = $true
        "yourDomain\Users" = $true
        "yourDomain\Administrators" = $true
        "" = $true
    }
    
    # Results collection
    $Results = [System.Collections.ArrayList]::new()
    
    # Function to write colored messages with timestamps
    function Write-LogMessage {
        param (
            [Parameter(Mandatory=$true)]
            [string]$Message,
            
            [Parameter()]
            [ValidateSet("Info", "Warning", "Error", "Success")]
            [string]$Level = "Info"
        )
        
        $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $ColorMap = @{
            "Info" = "White"
            "Warning" = "Yellow"
            "Error" = "Red"
            "Success" = "Green"
        }
        
        Write-Host "[$TimeStamp] " -NoNewline
        Write-Host $Message -ForegroundColor $ColorMap[$Level]
    }
    
    # Verify module is loaded
    if (-not (Get-Module -Name ActiveDirectory)) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Write-LogMessage "ActiveDirectory module loaded successfully." -Level Info
        }
        catch {
            Write-LogMessage "Failed to load ActiveDirectory module. Ensure it is installed." -Level Error
            Write-LogMessage "Error: $_" -Level Error
            exit 1
        }
    }
}

# Main script processing
Process {
    Write-LogMessage "This script helps you to extract all users from security groups that can access network folders." -Level Info
    Write-LogMessage "To run the script smoothly, ensure you do the following:" -Level Info
    Write-LogMessage "1- Create a .csv file with 'NetworkPath' as column header." -Level Info
    Write-LogMessage "2- Use the full path (E.G.: $DFSRoot\*), or $DriveLetter Drive ONLY." -Level Info
    Write-LogMessage "3- Run the script as an administrator." -Level Info
    Write-LogMessage "4- Move the file in your C:\Temp. (Easier as you run the script as Admin)." -Level Info
    
    Read-Host "Press Enter to continue"
    
    # Create psdrive with error handling
    try {
        if (-not (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue)) {
            New-PSDrive -Name $DriveLetter -PSProvider FileSystem -Root $DFSRoot -ErrorAction Stop | Out-Null
            Write-LogMessage "$DriveLetter drive mapped successfully to $DFSRoot" -Level Success
        }
        else {
            Write-LogMessage "$DriveLetter drive already exists, continuing with existing drive" -Level Info
        }
    }
    catch {
        Write-LogMessage "Failed to map $DriveLetter drive to $DFSRoot" -Level Error
        Write-LogMessage "Error: $_" -Level Error
        exit 1
    }
    
    # Ask User for the CSV file
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        
        $FileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $FileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $FileDialog.Title = "Select the CSV File for Processing"
        
        if ($FileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $CsvPath = $FileDialog.FileName
            Write-LogMessage "Selected File: $CsvPath" -Level Success
        }
        else {
            Write-LogMessage "No file selected. Exiting script." -Level Error
            exit
        }
    }
    catch {
        Write-LogMessage "Error creating file dialog: $_" -Level Error
        exit 1
    }
    
    # Validate the Selected File
    if (-not (Test-Path -Path $CsvPath)) {
        Write-LogMessage "Selected file does not exist. Exiting script." -Level Error
        exit
    }
    
    # Import and validate CSV
    try {
        $NetworkPaths = Import-Csv -Path $CsvPath -ErrorAction Stop
        
        # Validate CSV has the required header
        if (-not ($NetworkPaths | Get-Member -Name "NetworkPath")) {
            Write-LogMessage "CSV file does not contain required 'NetworkPath' column." -Level Error
            exit 1
        }
        
        Write-LogMessage "CSV file validated successfully. Found $($NetworkPaths.Count) paths." -Level Success
    }
    catch {
        Write-LogMessage "Error importing CSV file: $_" -Level Error
        exit 1
    }
    
    # Test path accessibility
    $ValidPaths = [System.Collections.ArrayList]::new()
    
    foreach ($PathEntry in $NetworkPaths) {
        $Path = $PathEntry.NetworkPath
        try {
            # Test if the path is accessible
            if (-not (Test-Path -Path $Path -ErrorAction Stop)) {
                Write-LogMessage "Path not reachable: $Path" -Level Warning
                
                # Prompt user to continue or exit
                do {
                    $Response = Read-Host "Path issues detected. Do you want to continue? (Yes/No)"
                    $Response = $Response.ToLower()
                } while ($Response -notin @("yes", "y", "no", "n"))
                
                if ($Response -in @("no", "n")) {
                    Write-LogMessage "Exiting script as requested." -Level Error
                    exit
                }
            }
            else {
                # Add the valid path to the list
                [void]$ValidPaths.Add($Path)
                Write-Verbose "Path validated: $Path"
            }
        }
        catch {
            Write-LogMessage "Error accessing path: $Path - $_" -Level Error
        }
    }
    
    # Process each valid network path
    $PathCount = $ValidPaths.Count
    $CurrentPath = 0
    
    foreach ($Path in $ValidPaths) {
        $CurrentPath++
        Write-LogMessage "Processing path ($CurrentPath/$PathCount): $Path" -Level Info
        
        try {
            # Get the ACL for the folder
            $Acl = Get-Acl -Path $Path -ErrorAction Stop
            
            # Extract security groups from the ACL - using hashtable for faster lookups
            $SecurityGroups = $Acl.Access | Where-Object {
                $_.IdentityReference.Value -like "YourDomain\*" -and
                -not $ExcludedGroups.ContainsKey($_.IdentityReference.Value)
            }
            
            # Handle cases where no domain-level groups are found
            if (-not $SecurityGroups) {
                Write-LogMessage "No domain-level security groups found for $Path. Skipping." -Level Warning
                continue
            }
            
            # Process each group
            foreach ($Group in $SecurityGroups) {
                # Remove domain prefix
                $GroupName = $Group.IdentityReference.Value -replace "^YourDomain\\", ""
                Write-Verbose "Processing Group: $GroupName"
                
                # Validate if the group exists in Active Directory
                try {
                    # Use server-side filtering for better performance
                    $ADGroup = Get-ADGroup -Filter "SamAccountName -eq '$GroupName'" -Properties ManagedBy -ErrorAction Stop
                    
                    if (-not $ADGroup) {
                        Write-LogMessage "Warning: Group '$GroupName' not found in AD. Skipping." -Level Warning
                        continue
                    }
                    
                    Write-Verbose "Valid Group Found in AD: $GroupName"
                    
                    # Retrieve the manager of the group
                    $ManagerName = "No Manager Assigned"
                    
                    if ($ADGroup.ManagedBy) {
                        try {
                            $GroupManager = Get-ADUser -Identity $ADGroup.ManagedBy -Properties DisplayName -ErrorAction SilentlyContinue
                            $ManagerName = if ($GroupManager) { 
                                $GroupManager.DisplayName 
                            } else { 
                                "Managed by: $($ADGroup.ManagedBy)" 
                            }
                        }
                        catch {
                            $ManagerName = "Error retrieving manager information"
                            Write-Verbose "Error getting manager: $_"
                        }
                    }
                    
                    Write-Verbose "Manager: $ManagerName"
                    
                    # Retrieve members of the valid group
                    try {
                        # For smaller groups, using Get-ADGroupMember is fine
                        $GroupMembers = Get-ADGroupMember -Identity $ADGroup.SamAccountName -Recursive -ErrorAction Stop
                        
                        # Process members
                        foreach ($Member in $GroupMembers) {
                            Write-Verbose "Member: $($Member.Name) ($($Member.ObjectClass))"
                            
                            # Add the details to the results collection (using ArrayList for better performance)
                            [void]$Results.Add([PSCustomObject]@{
                                NetworkPath = $Path
                                GroupName = $GroupName
                                UserName = $Member.Name
                                SecurityGroupManager = $ManagerName
                            })
                        }
                        
                        Write-LogMessage "Added $($GroupMembers.Count) members from group $GroupName" -Level Success
                    }
                    catch {
                        Write-LogMessage "Error retrieving members for group '$GroupName': $_" -Level Error
                    }
                }
                catch {
                    Write-LogMessage "Error processing group '$GroupName': $_" -Level Error
                }
            }
        }
        catch {
            Write-LogMessage "Error processing path $Path : $_" -Level Error
        }
    }
    
    # Export results to a CSV file
    try {
        # Create directory if it doesn't exist
        $ExportDir = Split-Path -Path $ExportPath -Parent
        if (-not (Test-Path -Path $ExportDir)) {
            New-Item -Path $ExportDir -ItemType Directory -Force | Out-Null
        }
        
        $Results | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-LogMessage "Export complete! CSV file saved to: $ExportPath" -Level Success
        Write-LogMessage "Total records exported: $($Results.Count)" -Level Success
    }
    catch {
        Write-LogMessage "Error exporting results: $_" -Level Error
    }
}

# Cleanup
End {
    # Remove psdrive
    try {
        if (Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue) {
            Remove-PSDrive -Name $DriveLetter -ErrorAction Stop -Force
            Write-LogMessage "$DriveLetter drive removed successfully" -Level Success
        }
    }
    catch {
        Write-LogMessage "Error removing drive $DriveLetter : $_" -Level Error
    }
    
    Write-LogMessage "Script execution completed" -Level Success
}
