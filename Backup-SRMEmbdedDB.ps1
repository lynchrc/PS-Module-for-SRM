<#


Must open PS as administrator

#>

[CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $DBUser,

    [Parameter(Mandatory=$True)]
    [string]
    $DBName,

    [Parameter(Mandatory=$False)]
    [string]
    $DBPort = 5678,

    [Parameter(Mandatory=$False)]
    [string]
    $ExpireDate = 7
    )

# Load vPostgreSQL Module
Import-Module vPostgreSQL -Force -WarningAction SilentlyContinue

# Set the date format for labels
$dateFormat = Format-Date
# Date Format:  2018-04-10_105422

# Get Backup Executable
$vBackupPath = Get-BackupPath
# Backup Path:  E:\Program Files\VMware\VMware vCenter Site Recovery Manager Embedded Database\bin\pg_dump.exe


# Get Drive Letter from $vBackupPath
$driveLetter = Split-Path -Path $vBackupPath -Qualifier
# Drive Letter:  E:

# Check to see if backup root folder exists, if not create it
$backupRootDir = Check-BackupRootDir -DriveLetter $driveLetter 
# Backup root FullName E:\vPostgres-Backup 

# Create daily backup folder
$dailyBackupFolder = Create-DailyBackupDir -BackupRootDir $backupRootDir.FullName -DateFormat $dateFormat
# Daily Backup Path Full Name: $dailyBackupFolder.FullName       E:\vPostgres-Backup\DailyBackup2018-04-10_121119

# Create Logfile and log current info so far
$logFileName = "Backup-Log.log"
$logFile = Join-Path $dailyBackupFolder.FullName$logFileName
Write-Log -Level INFO -Message "Daily Backup foder [ $dailyBackupFolder ] was created." -LogFile $logFile

# Get size of last backup
$lastBackupSize = 0
$backupFolderCount = Get-ChildItem -Directory -Path $backupRootDir.FullName | Measure-Object
if ($backupFolderCount.Count -ge 2) {
    $backupFolders = Get-ChildItem -Directory -Path $backupRootDir.FullName
    $lastBackupFolder = $backupFolders[-2]
    $lastBackupSize = Get-FolderSize -FolderPath $lastBackupFolder.FullName
    Write-Log -Level INFO -Message "Last Backup size was: $lastBackupSize" -Logfile $logFile
}
Else { 
    $lastBackupSize
    Write-Log -Level INFO -Message "Last Backup size was: $lastBackupSize" -Logfile $logFile
}


# Get the backup drive free space
$freeSpace = Get-BackupDriveFreeDiskSpace -BackupDrive $driveLetter
Write-Log -Level INFO -Message "Availabe free space is: $freeSpace GB" -Logfile $logFile

# Check that there is enough space to perform a backup
$isFreeSpace = Check-AvailableBackupSpace -LastBackupSize $lastBackupSize -FreeSpace $freeSpace -Overhead 10


If ($isFreeSpace -eq $false) {
    Write-Log -Level CRITICAL -Message "There is not enough space to perform a backup"
    Exit
}
Else {
    # Start a timer
    $startTimer = (Get-Date);

    Write-Log -Level INFO -Message "Starting Backup Process" -Logfile $logFile

    # Stop the SRM Service
    Toggle-SRMService -State STOP -Logfile $logFile

    # Start the backup
    Backup-vPostgreSQL -BackupCommand $vBackupPath -DatabaseUser $DBUser -DatabaseName $DBName -DailyBackupFolder $dailyBackupFolder -Port $DBPort -Logfile $logFile

    # Start the SRM Service
    Toggle-SRMService -State START -Logfile $logFile

    # Log backup duration
    $ElapsedTime = $(get-date) - $startTimer
    $minutes = $ElapsedTime.Minutes
    $seconds = $ElapsedTime.Seconds
    Write-Log -Level INFO -Message "Backup completed in [ $minutes minutes and $seconds seconds ] " -Logfile $logFile
    
}

Remove-OldBackup -BackupRoot $backupRootDir.FullName -ExpireDate $ExpireDate -LogFile $logFile