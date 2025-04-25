# LoggingHelpers.psm1
<#
.SYNOPSIS
    A reusable PowerShell logging module providing configurable and flexible logging capabilities.
.DESCRIPTION
    This module offers two primary functions:
    1. Set-LogConfiguration - Configure default logging parameters
    2. Add-LogEntry - Write log entries with customizable severity levels
    
    The module supports persistent configuration, customizable log paths, and color-coded console output.
    
    WARNINGS AND BEST PRACTICES:
    - If multiple scripts use this module simultaneously with SaveConfig, they might overwrite each other's configurations.
    - For occasional script usage, prefer using Set-LogConfiguration without the SaveConfig parameter.
    - For permanent scripts, use the ScriptSpecific parameter to maintain separate configurations per script.
    - Choose appropriate log paths with proper permissions to avoid write access issues.
    - Be mindful of disk space when logging extensively; the module does not automatically clean old log files.
.NOTES
    Author: Thomas Bonnet
    Version: 1.1
    Date: 2025-04-18
.EXAMPLE
    # Simple usage without prior configuration
    Add-LogEntry -Level INFO -Message "Script started"
    
    # Set default configuration
    Set-LogConfiguration -DefaultPath "C:\logs\MyApp" -DefaultLevel INFO
    
    # Use with default configuration
    Add-LogEntry -Message "Processing started"
    
    # Script-specific configuration
    Set-LogConfiguration -DefaultPath "C:\logs\MyScript" -ScriptSpecific $true -SaveConfig $true
    
    # Override configuration for a specific entry
    Add-LogEntry -Level ERROR -Message "Critical error detected" -LogPath "C:\temp\debug"
#>

# Script-level variables for configuration
$script:LogConfig = @{
    DefaultPath = $null
    DefaultLevel = "INFO"
    DisplayInConsole = $true
    CreateMissingFolders = $true
    DateFormat = "yyyy-MM-dd HH:mm:ss"
    LogFilePrefix = "Log_"
    LogFileDateFormat = "yyyyMMdd"
    MaxFileSizeMB = 10
    ConfigPath = "$PSScriptRoot\LogConfig.json"
}

# Generate a unique session ID if we're not already using a specific configuration
if (-not (Test-Path -Path $script:LogConfig.ConfigPath)) {
    $SessionId = [System.Guid]::NewGuid().ToString()
    $script:LogConfig.ConfigPath = Join-Path -Path $env:TEMP -ChildPath "LogConfig_$SessionId.json"
    Write-Verbose "Using session-specific configuration: $($script:LogConfig.ConfigPath)"
}

<#
.SYNOPSIS
    Configures default logging parameters.
.DESCRIPTION
    Sets and persists default configuration for the logging system.
    Configuration can be saved to a JSON file for persistence across sessions.
.PARAMETER DefaultPath
    The default path where log files will be stored.
.PARAMETER DefaultLevel
    The default logging level (INFO, WARNING, ERROR, DEBUG, SUCCESS).
.PARAMETER DisplayInConsole
    Whether to display log entries in the console in addition to writing to file.
.PARAMETER CreateMissingFolders
    Whether to automatically create log folders if they don't exist.
.PARAMETER DateFormat
    The format to use for timestamps in log entries.
.PARAMETER LogFilePrefix
    Prefix to use for log files.
.PARAMETER LogFileDateFormat
    Date format to use in log filenames for daily rotation.
.PARAMETER MaxFileSizeMB
    Maximum size in MB before rotating log files.
.PARAMETER SaveConfig
    Whether to save the configuration to a JSON file for persistence.
.EXAMPLE
    Set-LogConfiguration -DefaultPath "C:\logs\MyApp" -DefaultLevel INFO -SaveConfig $true
#>
function Set-LogConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$DefaultPath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
        [string]$DefaultLevel = "INFO",
        
        [Parameter(Mandatory=$false)]
        [bool]$DisplayInConsole = $true,
        
        [Parameter(Mandatory=$false)]
        [bool]$CreateMissingFolders = $true,
        
        [Parameter(Mandatory=$false)]
        [string]$DateFormat = "yyyy-MM-dd HH:mm:ss",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePrefix = "Log_",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFileDateFormat = "yyyyMMdd",
        
        [Parameter(Mandatory=$false)]
        [int]$MaxFileSizeMB = 10,
        
        [Parameter(Mandatory=$false)]
        [bool]$SaveConfig = $false,
        
        [Parameter(Mandatory=$false)]
        [bool]$ScriptSpecific = $false
    )

    # Default path is script location/logs if not provided
    if (-not $DefaultPath) {
        # Vérifier si C:\logs existe ou peut être créé
        if ((Test-Path -Path "C:\logs") -or 
            (Test-Path -Path "C:\" -and (New-Item -Path "C:\logs" -ItemType Directory -Force -ErrorAction SilentlyContinue))) {
            $DefaultPath = "C:\logs"
        } else {
            # Fallback to the script directory if C:\logs is not accessible.
            $DefaultPath = Join-Path -Path $PSScriptRoot -ChildPath "logs"
        }
    }
    
    # Handle script-specific configuration
    if ($ScriptSpecific) {
        $CallingScript = if ($MyInvocation.ScriptName) { 
            Split-Path -Path $MyInvocation.ScriptName -Leaf 
        } else { 
            "PowerShell" 
        }
        
        # Remove the .ps1 extension
        $ScriptBaseName = [System.IO.Path]::GetFileNameWithoutExtension($CallingScript)
        
        # Create a script-specific config path
        $script:LogConfig.ConfigPath = "$PSScriptRoot\LogConfig_$ScriptBaseName.json"
        Write-Verbose "Using script-specific configuration: $($script:LogConfig.ConfigPath)"
    }
    
    # Update configuration
    $script:LogConfig.DefaultPath = $DefaultPath
    $script:LogConfig.DefaultLevel = $DefaultLevel
    $script:LogConfig.DisplayInConsole = $DisplayInConsole
    $script:LogConfig.CreateMissingFolders = $CreateMissingFolders
    $script:LogConfig.DateFormat = $DateFormat
    $script:LogConfig.LogFilePrefix = $LogFilePrefix
    $script:LogConfig.LogFileDateFormat = $LogFileDateFormat
    $script:LogConfig.MaxFileSizeMB = $MaxFileSizeMB
    
    # Save configuration if requested
    if ($SaveConfig) {
        $ConfigDir = Split-Path -Path $script:LogConfig.ConfigPath -Parent
        if (-not (Test-Path -Path $ConfigDir)) {
            New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
        }
        
        $script:LogConfig | ConvertTo-Json | Out-File -FilePath $script:LogConfig.ConfigPath -Force
        Write-Verbose "Log configuration saved to $($script:LogConfig.ConfigPath)"
    }
    
    # Return the configuration
    return $script:LogConfig
}

<#
.SYNOPSIS
    Adds a log entry to the log file and optionally displays it in the console.
.DESCRIPTION
    Creates a standardized log entry with timestamp, severity level, and message.
    Automatically handles log file creation and folder creation if needed.
.PARAMETER Level
    The severity level of the log entry (INFO, WARNING, ERROR, DEBUG, SUCCESS).
.PARAMETER Message
    The log message to record.
.PARAMETER LogPath
    The path where the log file should be stored. Overrides the default path if specified.
.PARAMETER Context
    Additional contextual information to include with the log entry.
.PARAMETER Display
    Whether to display this specific log entry in the console regardless of default setting.
.EXAMPLE
    Add-LogEntry -Level ERROR -Message "Failed to connect to server" -Context "Timeout: 30s"
.EXAMPLE
    Add-LogEntry -Message "Process completed successfully" -Level SUCCESS
#>
function Add-LogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG", "SUCCESS")]
        [string]$Level,
        
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$LogPath,
        
        [Parameter(Mandatory=$false)]
        [string]$Context,
        
        [Parameter(Mandatory=$false)]
        [bool]$Display
    )
    
    # Try to load saved configuration if exists and not yet loaded
    if ((-not $script:LogConfig.DefaultPath) -and (Test-Path -Path $script:LogConfig.ConfigPath)) {
        try {
            $SavedConfig = Get-Content -Path $script:LogConfig.ConfigPath | ConvertFrom-Json
            foreach ($Key in $SavedConfig.PSObject.Properties.Name) {
                $script:LogConfig[$Key] = $SavedConfig.$Key
            }
            Write-Verbose "Loaded log configuration from $($script:LogConfig.ConfigPath)"
        }
        catch {
            Write-Verbose "Error loading log configuration: $_"
        }
    }
    
    # Use default level if not specified
    if (-not $Level) {
        $Level = $script:LogConfig.DefaultLevel
    }
    
    # Use default log path if not specified
    if (-not $LogPath) {
        if ($script:LogConfig.DefaultPath) {
            $LogPath = $script:LogConfig.DefaultPath
        }
        else {
            # Use script location/logs if no default path is configured
            $LogPath = Join-Path -Path $PSScriptRoot -ChildPath "logs"
        }
    }
    
    # Create log directory if it doesn't exist
    if ($script:LogConfig.CreateMissingFolders -and -not (Test-Path -Path $LogPath)) {
        try {
            New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
            Write-Verbose "Created log directory: $LogPath"
        }
        catch {
            Write-Warning "Failed to create log directory: $_"
            return
        }
    }
    
    # Determine log file name (using date for daily rotation)
    $DatePart = Get-Date -Format $script:LogConfig.LogFileDateFormat
    $LogFileName = "$($script:LogConfig.LogFilePrefix)$DatePart.log"
    $LogFilePath = Join-Path -Path $LogPath -ChildPath $LogFileName
    
    # Create timestamp
    $Timestamp = Get-Date -Format $script:LogConfig.DateFormat
    
    # Get calling script name
    $CallingScript = if ($MyInvocation.ScriptName) { 
        Split-Path -Path $MyInvocation.ScriptName -Leaf 
    } 
    else { 
        "PowerShell" 
    }
    
    # Build log entry
    $LogEntry = "[$Timestamp] [$Level] [$CallingScript] $Message"
    
    # Add context if provided
    if ($Context) {
        $LogEntry += " | Context: $Context"
    }
    
    # Write to log file
    try {
        Add-Content -Path $LogFilePath -Value $LogEntry
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
    
    # Determine if we should display in console
    $ShouldDisplay = if ($null -ne $Display) { 
        $Display 
    } 
    else { 
        $script:LogConfig.DisplayInConsole 
    }
    
    # Display in console if enabled
    if ($ShouldDisplay) {
        # Set color based on level
        $Color = switch ($Level) {
            "ERROR"   { "Red" }
            "WARNING" { "Yellow" }
            "INFO"    { "White" }
            "DEBUG"   { "Cyan" }
            "SUCCESS" { "Green" }
            default   { "White" }
        }
        
        Write-Host $LogEntry -ForegroundColor $Color
    }
}

# Load saved configuration if it exists
if (Test-Path -Path $script:LogConfig.ConfigPath) {
    try {
        $SavedConfig = Get-Content -Path $script:LogConfig.ConfigPath | ConvertFrom-Json
        foreach ($Key in $SavedConfig.PSObject.Properties.Name) {
            $script:LogConfig[$Key] = $SavedConfig.$Key
        }
        Write-Verbose "Loaded log configuration from $($script:LogConfig.ConfigPath)"
    }
    catch {
        Write-Verbose "Error loading log configuration: $_"
    }
}

# Clean up temporary file when the session ends
$SessionStateCleanup = [scriptblock]::Create(@"
    if (Test-Path -Path "$($script:LogConfig.ConfigPath)" -and 
        "$($script:LogConfig.ConfigPath)" -like "*$env:TEMP*LogConfig_*-*-*-*-*.json") {
        Remove-Item -Path "$($script:LogConfig.ConfigPath)" -Force -ErrorAction SilentlyContinue
    }
"@)

# Register cleanup event
Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) -Action $SessionStateCleanup

# Export module functions
Export-ModuleMember -Function Set-LogConfiguration, Add-LogEntry