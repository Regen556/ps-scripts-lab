<#
.SYNOPSIS
    Displays a file selection dialog and returns the selected file path.
.DESCRIPTION
    This function presents a graphical file selection dialog to the user,
    allowing them to browse and select a file without typing the full path.
    It supports filtering by file types and remembers the last used directory.
.PARAMETER Title
    The title to display in the file selection dialog window.
.PARAMETER FileTypes
    The file types to filter by. Default is "All files (*.*)|*.*".
    Example: "CSV files (*.csv)|*.csv|Text files (*.txt)|*.txt"
.PARAMETER InitialDirectory
    The starting directory for the file browser. If not specified,
    it will use the last directory or default to the user's Documents folder.
.PARAMETER SaveLastDirectory
    If set to $true, saves the last directory browsed for future use.
.RETURNS
    The full path to the selected file, or $null if canceled.
.NOTES
    Author: Thomas "Regen" Bonnet
    Version: 1.0
    Date: 03-02-2025
.EXAMPLE
    # Select a CSV file
    $csvPath = Select-FileDialog -Title "Select CSV file" -FileTypes "CSV files (*.csv)|*.csv"
    
    if ($csvPath) {
        Import-Csv $csvPath
    } else {
        Write-Host "Operation canceled by user."
    }
#>
function Select-FileDialog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Title = "Select a file",
        
        [Parameter(Mandatory=$false)]
        [string]$FileTypes = "All files (*.*)|*.*",
        
        [Parameter(Mandatory=$false)]
        [string]$InitialDirectory = $null,
        
        [Parameter(Mandatory=$false)]
        [bool]$SaveLastDirectory = $true
    )

    # Function logic would be implemented here
    # It would return the selected file path or $null if canceled
}
