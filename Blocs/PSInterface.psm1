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
    The starting directory for the file browser. 
    It will use the last directory or default to the user's Documents folder if not specified.
.PARAMETER SaveLastDirectory
    If set to $true, saves the last directory browsed for future use.
.RETURNS
    The full path to the selected file, or $null if canceled.
.NOTES
    Author: Thomas Bonnet
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
        [ValidateSet('OpenFile','SaveFile','Folder')]
        [string] $Mode = 'OpenFile',

        [string] $Title = 'Select a path',
        
        # Only used by the two file dialogs
        [string] $Filter = 'All files (*.*)|*.*',

        [string] $InitialDirectory = $null,

        [switch] $SaveLastDirectory
    )

    # Load WinForms once per session
    if (-not ([System.Windows.Forms.Application]::MessageLoop)) {
        Add-Type -AssemblyName System.Windows.Forms
    }

    # --- create the right dialog ------------------------------------------------
    switch ($Mode) {
        'OpenFile' { $dlg = New-Object System.Windows.Forms.OpenFileDialog  }
        'SaveFile' { $dlg = New-Object System.Windows.Forms.SaveFileDialog  }
        'Folder'   { $dlg = New-Object System.Windows.Forms.FolderBrowserDialog }
    }

    $dlg.Title = $Title

    if ($dlg -is [System.Windows.Forms.FileDialog]) {    # the two file pickers
        $dlg.Filter = $Filter
        if ($InitialDirectory) {
            $dlg.InitialDirectory = $InitialDirectory
        } elseif ($SaveLastDirectory -and $global:LastDialogDir -and (Test-Path $global:LastDialogDir)) {
            $dlg.InitialDirectory = $global:LastDialogDir
        } else {
            $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        }
    } elseif ($dlg -is [System.Windows.Forms.FolderBrowserDialog]) { # folder picker
        if ($InitialDirectory) { $dlg.SelectedPath = $InitialDirectory }
        elseif ($SaveLastDirectory -and $global:LastDialogDir -and (Test-Path $global:LastDialogDir)) {
            $dlg.SelectedPath = $global:LastDialogDir
        }
    }

    # --- show the dialog --------------------------------------------------------
    $result = $dlg.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Get the chosen path & remember its directory (for next time, if wanted)
        switch ($Mode) {
            'OpenFile' { $path = $dlg.FileName }
            'SaveFile' { $path = $dlg.FileName }
            'Folder'   { $path = $dlg.SelectedPath }
        }
        if ($SaveLastDirectory) {
            $global:LastDialogDir = if ($Mode -eq 'Folder') { $path }
                                     else { [System.IO.Path]::GetDirectoryName($path) }
        }
        return $path
    }

    return $null  # user cancelled
}
