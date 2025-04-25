# LoggingHelpers.psm1
<#
.SYNOPSIS
    A reusable PowerShell logging module providing configurable and flexible logging capabilities.
.DESCRIPTION
    PSReboot provides a framework for creating scripts that can continue
    execution after system reboots. It manages state persistence, scheduled
    tasks, and workflow resumption automatically.

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

    NOTE: This module can integrate with PSLogger for enhanced logging capabilities.
    To enable this integration, simply install and import PSLogger in your script
    before importing PSReboot.

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

#region Module Variables
# Default configuration settings
$script:LogDefaultPath = "$env:TEMP\PowerShell-Logs"
$script:LogDefaultLevel = "INFO"
$script:LogToConsole = $true
$script:LogToFile = $true
$script:LogMaxSize = 10MB  # Maximum log file size before rotation
$script:LogRetention = 30  # Number of days to keep logs
$script:ScriptSpecificConfig = $false
$script:CurrentScriptName = ""
$script:ConfigStoragePath = "$env:APPDATA\PowerShell\LoggingHelpers"
$script:DefaultConfigFile = "$script:ConfigStoragePath\config.json"

# PSReboot specific paths
$script:StateStoragePath = "$env:ProgramData\PSReboot"
$script:StateFile = "$script:StateStoragePath\state.json"
$script:LogFile = "$script:StateStoragePath\PSReboot.log"
$script:ScheduledTaskName = "PSReboot-AutoContinue"
$script:DefaultPriority = 4 # Use SYSTEM_MANDATORY_LABEL for high priority

# Check if PSLogger is already loaded
$script:PSLoggerAvailable = $null -ne (Get-Module -Name PSLogger -ErrorAction SilentlyContinue)

# If detected, output a verbose message
if ($script:PSLoggerAvailable) {
    Write-Verbose "PSLogger detected. Enhanced logging enabled."
}

#endregion

#region Internal Functions
function Initialize-LoggingEnvironment {
    [CmdletBinding()]
    param()
    
    # Create config directory if it doesn't exist
    if (-not (Test-Path -Path $script:ConfigStoragePath -PathType Container)) {
        New-Item -Path $script:ConfigStoragePath -ItemType Directory -Force | Out-Null
    }
    
    # If a saved configuration exists, load it
    if (Test-Path -Path $script:DefaultConfigFile) {
        $savedConfig = Get-Content -Path $script:DefaultConfigFile -Raw | ConvertFrom-Json
        $script:LogDefaultPath = $savedConfig.DefaultPath
        $script:LogDefaultLevel = $savedConfig.DefaultLevel
        $script:LogToConsole = $savedConfig.ToConsole
        $script:LogToFile = $savedConfig.ToFile
        $script:LogMaxSize = $savedConfig.MaxSize
        $script:LogRetention = $savedConfig.Retention
        $script:ScriptSpecificConfig = $savedConfig.ScriptSpecific
    }
    
    # If script-specific configs are enabled, try to get current script name
    if ($script:ScriptSpecificConfig) {
        $callStack = Get-PSCallStack
        if ($callStack.Count -gt 1) {
            $callingScript = $callStack[1].ScriptName
            if ($callingScript) {
                $script:CurrentScriptName = [System.IO.Path]::GetFileNameWithoutExtension($callingScript)
            }
        }
    }
}

function Get-ScriptSpecificConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptName = $script:CurrentScriptName
    )
    
    if ([string]::IsNullOrEmpty($ScriptName)) {
        return $script:DefaultConfigFile
    }
    
    return "$script:ConfigStoragePath\$ScriptName-config.json"
}

function Get-CurrentConfig {
    [CmdletBinding()]
    param()
    
    # If script-specific configs are enabled and we have a script name
    if ($script:ScriptSpecificConfig -and -not [string]::IsNullOrEmpty($script:CurrentScriptName)) {
        $configPath = Get-ScriptSpecificConfigPath
        if (Test-Path -Path $configPath) {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            return $config
        }
    }
    
    # Return default config
    return [PSCustomObject]@{
        DefaultPath = $script:LogDefaultPath
        DefaultLevel = $script:LogDefaultLevel
        ToConsole = $script:LogToConsole
        ToFile = $script:LogToFile
        MaxSize = $script:LogMaxSize
        Retention = $script:LogRetention
        ScriptSpecific = $script:ScriptSpecificConfig
    }
}

function Save-CurrentConfig {
    [CmdletBinding()]
    param()
    
    $config = [PSCustomObject]@{
        DefaultPath = $script:LogDefaultPath
        DefaultLevel = $script:LogDefaultLevel
        ToConsole = $script:LogToConsole
        ToFile = $script:LogToFile
        MaxSize = $script:LogMaxSize
        Retention = $script:LogRetention
        ScriptSpecific = $script:ScriptSpecificConfig
    }
    
    # Determine where to save the config
    $configPath = if ($script:ScriptSpecificConfig -and -not [string]::IsNullOrEmpty($script:CurrentScriptName)) {
        Get-ScriptSpecificConfigPath
    } else {
        $script:DefaultConfigFile
    }
    
    # Save the config
    $config | ConvertTo-Json | Out-File -FilePath $configPath -Force
}

function Get-LogFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$LogPath = $script:LogDefaultPath
    )
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogPath -PathType Container)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Generate log filename with date
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $logFileName = if (-not [string]::IsNullOrEmpty($script:CurrentScriptName) -and $script:ScriptSpecificConfig) {
        "$($script:CurrentScriptName)_$currentDate.log"
    } else {
        "PowerShell_$currentDate.log"
    }
    
    return Join-Path -Path $LogPath -ChildPath $logFileName
}

function Rotate-LogFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )
    
    # Check if log file exceeds maximum size
    if ((Test-Path -Path $LogFile) -and ((Get-Item -Path $LogFile).Length -gt $script:LogMaxSize)) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $newName = [System.IO.Path]::GetFileNameWithoutExtension($LogFile) + "_$timestamp" + [System.IO.Path]::GetExtension($LogFile)
        $newPath = Join-Path -Path (Split-Path -Path $LogFile -Parent) -ChildPath $newName
        
        Move-Item -Path $LogFile -Destination $newPath -Force
    }
    
    # Clean up old log files
    $logDir = Split-Path -Path $LogFile -Parent
    $cutoffDate = (Get-Date).AddDays(-$script:LogRetention)
    
    Get-ChildItem -Path $logDir -Filter "*.log" | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | Remove-Item -Force
}

function Get-LevelColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Level
    )
    
    switch ($Level.ToUpper()) {
        "DEBUG" { return "Gray" }
        "INFO" { return "White" }
        "WARNING" { return "Yellow" }
        "ERROR" { return "Red" }
        "SUCCESS" { return "Green" }
        "CRITICAL" { return "Magenta" }
        default { return "White" }
    }
}
#endregion

#region Exported Functions
<#
.SYNOPSIS
    Configures the default logging behavior for the LoggingHelpers module.
.DESCRIPTION
    This function allows you to set up the default behavior for the Add-LogEntry function.
    You can configure the default log path, level, and output options.
.PARAMETER DefaultPath
    The default directory path where log files will be stored.
.PARAMETER DefaultLevel
    The default logging level to use when no level is specified (DEBUG, INFO, WARNING, ERROR, SUCCESS, CRITICAL).
.PARAMETER LogToConsole
    Indicates whether log entries should be written to the console.
.PARAMETER LogToFile
    Indicates whether log entries should be written to a file.
.PARAMETER MaxSize
    Maximum size for log files before rotation occurs.
.PARAMETER Retention
    Number of days to keep log files before automatic cleanup.
.PARAMETER ScriptSpecific
    Indicates whether to use script-specific configurations.
.PARAMETER SaveConfig
    Indicates whether to save the configuration for future sessions.
.EXAMPLE
    Set-LogConfiguration -DefaultPath "C:\Logs\MyApp" -DefaultLevel "INFO" -SaveConfig $true
    Configures the module to write INFO-level logs to the specified directory and saves this configuration.
.EXAMPLE
    Set-LogConfiguration -LogToConsole $true -LogToFile $false
    Configures the module to only write to the console, not to files.
#>
function Set-LogConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$DefaultPath,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS", "CRITICAL")]
        [string]$DefaultLevel,
        
        [Parameter(Mandatory = $false)]
        [bool]$LogToConsole,
        
        [Parameter(Mandatory = $false)]
        [bool]$LogToFile,
        
        [Parameter(Mandatory = $false)]
        [long]$MaxSize,
        
        [Parameter(Mandatory = $false)]
        [int]$Retention,
        
        [Parameter(Mandatory = $false)]
        [bool]$ScriptSpecific,
        
        [Parameter(Mandatory = $false)]
        [bool]$SaveConfig = $false
    )
    
    # Initialize environment
    Initialize-LoggingEnvironment
    
    # Update parameters if provided
    if ($PSBoundParameters.ContainsKey('DefaultPath')) {
        $script:LogDefaultPath = $DefaultPath
    }
    
    if ($PSBoundParameters.ContainsKey('DefaultLevel')) {
        $script:LogDefaultLevel = $DefaultLevel
    }
    
    if ($PSBoundParameters.ContainsKey('LogToConsole')) {
        $script:LogToConsole = $LogToConsole
    }
    
    if ($PSBoundParameters.ContainsKey('LogToFile')) {
        $script:LogToFile = $LogToFile
    }
    
    if ($PSBoundParameters.ContainsKey('MaxSize')) {
        $script:LogMaxSize = $MaxSize
    }
    
    if ($PSBoundParameters.ContainsKey('Retention')) {
        $script:LogRetention = $Retention
    }
    
    if ($PSBoundParameters.ContainsKey('ScriptSpecific')) {
        $script:ScriptSpecificConfig = $ScriptSpecific
        
        # If ScriptSpecific is enabled, try to get current script name
        if ($ScriptSpecific) {
            $callStack = Get-PSCallStack
            if ($callStack.Count -gt 1) {
                $callingScript = $callStack[1].ScriptName
                if ($callingScript) {
                    $script:CurrentScriptName = [System.IO.Path]::GetFileNameWithoutExtension($callingScript)
                }
            }
        }
    }
    
    # Save configuration if requested
    if ($SaveConfig) {
        Save-CurrentConfig
    }
    
    # Return the current configuration
    return Get-CurrentConfig
}

<#
.SYNOPSIS
    Adds a log entry with the specified level and message.
.DESCRIPTION
    This function adds a log entry to the console and/or a log file, depending on configuration.
    It supports various log levels and can override the default log path if needed.
.PARAMETER Level
    The severity level of the log entry (DEBUG, INFO, WARNING, ERROR, SUCCESS, CRITICAL).
.PARAMETER Message
    The message to log.
.PARAMETER LogPath
    Optional. Override the default log directory path for this entry.
.PARAMETER NoConsole
    Optional. Suppresses console output for this entry, regardless of configuration.
.PARAMETER NoFile
    Optional. Suppresses file output for this entry, regardless of configuration.
.EXAMPLE
    Add-LogEntry -Level INFO -Message "Process started"
    Logs an informational message using default configuration.
.EXAMPLE
    Add-LogEntry -Level ERROR -Message "Connection failed" -LogPath "C:\Temp\Errors"
    Logs an error message to the specified directory, overriding the default.
.EXAMPLE
    Add-LogEntry -Message "Operation completed"
    Logs a message with the default level (typically INFO).
#>
function Add-LogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS", "CRITICAL")]
        [string]$Level = $script:LogDefaultLevel,
        
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [string]$LogPath,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoFile
    )
    
    # Initialize environment
    Initialize-LoggingEnvironment
    
    # Get current config
    $currentConfig = Get-CurrentConfig
    
    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format log entry
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console if enabled
    if ($currentConfig.ToConsole -and -not $NoConsole) {
        $color = Get-LevelColor -Level $Level
        Write-Host $logEntry -ForegroundColor $color
    }
    
    # Write to file if enabled
    if ($currentConfig.ToFile -and -not $NoFile) {
        $logFilePath = if ($LogPath) {
            Get-LogFilePath -LogPath $LogPath
        } else {
            Get-LogFilePath -LogPath $currentConfig.DefaultPath
        }
        
        # Rotate log file if needed
        Rotate-LogFile -LogFile $logFilePath
        
        # Write log entry to file
        Add-Content -Path $logFilePath -Value $logEntry -Encoding UTF8
    }
}

<#
.SYNOPSIS
    Retrieves the current logging configuration.
.DESCRIPTION
    This function returns the current logging configuration, including default path, level, and output options.
.EXAMPLE
    Get-LogConfiguration
    Returns the current logging configuration.
#>
function Get-LogConfiguration {
    [CmdletBinding()]
    param()
    
    # Initialize environment
    Initialize-LoggingEnvironment
    
    # Return current configuration
    return Get-CurrentConfig
}

<#
.SYNOPSIS
    Clears all logging configurations and resets to default values.
.DESCRIPTION
    This function removes all saved configurations and resets the module to its default state.
    It can optionally remove only script-specific configurations.
.PARAMETER ScriptSpecificOnly
    If set, only clears script-specific configurations.
.EXAMPLE
    Clear-LogConfiguration
    Removes all saved configurations and resets to defaults.
.EXAMPLE
    Clear-LogConfiguration -ScriptSpecificOnly
    Removes only script-specific configurations.
#>
function Clear-LogConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$ScriptSpecificOnly
    )
    
    if ($ScriptSpecificOnly) {
        # Remove script-specific config files only
        if (Test-Path $script:ConfigStoragePath) {
            Get-ChildItem -Path $script:ConfigStoragePath -Filter "*-config.json" | Remove-Item -Force
        }
    } else {
        # Remove all config files
        if (Test-Path $script:ConfigStoragePath) {
            Get-ChildItem -Path $script:ConfigStoragePath -Filter "*.json" | Remove-Item -Force
        }
        
        # Reset to default values
        $script:LogDefaultPath = "$env:TEMP\PowerShell-Logs"
        $script:LogDefaultLevel = "INFO"
        $script:LogToConsole = $true
        $script:LogToFile = $true
        $script:LogMaxSize = 10MB
        $script:LogRetention = 30
        $script:ScriptSpecificConfig = $false
        $script:CurrentScriptName = ""
    }
}
#endregion

# Initialize module on import
Initialize-LoggingEnvironment

# Export functions
Export-ModuleMember -Function Set-LogConfiguration, Add-LogEntry, Get-LogConfiguration, Clear-LogConfiguration