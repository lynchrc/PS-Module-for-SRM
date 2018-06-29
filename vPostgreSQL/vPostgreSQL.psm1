Function Write-Log {
    <#
    .SYNOPSIS
    This function creates a logfile

    .DESCRIPTION
    This function creates a logfile and allows the user to create 5 types of log updates with timestamps

    .PARAMETER Level
    Specifies the logging level

    .PARAMETER Message
    Specifies the message to log

    .PARAMETER Logfile
    Specifies the file to log to

    .EXAMPLE
    Write-Log -Level DEBUG -Message "Hello World!" -Logfile "C:\ApplicationFolder\Application.log"
    #>

    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [ValidateSet("DEBUG","INFO","WARNING","ERROR","CRITICAL")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $Logfile
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp  [$Level] -- $Message"
    If($logfile) {
        Add-Content $logfile -Value $Line
    }
    Else {
        Write-Output $Line
    }
}


Function Get-BackupDriveFreeDiskSpace {
    <#
    .SYNOPSIS
    This function gets the free disk space for the backup drive

    .DESCRIPTION
    This function takes the backup drive as a parameter and get the available disk space

    .PARAMETER BackupDrive
    Specifies the drive for backups

    .EXAMPLE
    Get-BackupDriveFreeDiskSpace -BackupDrive 'E:\Program Files\PostgreSQL\9.3\bin\pg_basebackup.exe'
    #>

    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $BackupDrive
    )

    $backupDriveLetter = Split-Path -Path $BackupDrive -Qualifier
    $freeSpace = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID = '$backupDriveLetter'" | Select FreeSpace
    $prettyFreeSpace = [Math]::Round($freeSpace.FreeSpace /1GB, 2)
    return $prettyFreeSpace        
     
}


Function Get-BackupPath{
    <#
    .SYNOPSIS
    This function gets the path backup executable

    .DESCRIPTION
    This function check the services for the vpostgres DB and uses its PathName to get the path to the backup executable

    .EXAMPLE
    $vBackupPath = Get-BackupPath
    #>
    $vDbServiceName = 'vmware-dr-vpostgres'
    $vDbServiceInfo = Get-WmiObject -Class Win32_Service | where {$_.Name -match $vDbServiceName}
    $servicePath = $vDbServiceInfo.PathName
    $subString = $servicePath.Substring(1,2) 
    $vBackupPath = Get-ChildItem $subString -Recurse | where {$_.Name -match 'pg_dump.exe'} | Select FullName
    return $vBackupPath.FullName 
}


function Toggle-SRMService {
    <#
    .SYNOPSIS
    This function stops or starts the SRM service

    .DESCRIPTION
    This function takes input wither stop or start and performs this action on the VMware SRM service

    .PARAMETER State
    Specifies the action you would like to take on the SRM service

    .EXAMPLE
    Toggle-SRMService -State STOP

    .EXAMPLE
    Toggle-SRMService -State START
    #>
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [ValidateSet("STOP","START")]
    [String]
    $State,

    [Parameter(Mandatory=$False)]
    [string]
    $Logfile
    
    )

    $serviceName = 'vmware-dr'

    switch($State.ToUpper()) {
        START {write-host "Need to start service"
            Write-Log -Level INFO -Message "Starting $serviceName service" -Logfile $Logfile
            Start-Service $serviceName -ErrorAction SilentlyContinue
            if ( -not $?) {
                Write-Log -Level ERROR -Message "Could not start service;" -Logfile $Logfile
                Exit
            }
            break;
        }
        STOP {Write-Host "Need to stop service"
            Write-Log -Level INFO -Message "Stopping $serviceName service" -Logfile $Logfile
            Stop-Service $serviceName -ErrorAction SilentlyContinue
            if( -not $?) {
                Write-Log -Level ERROR -Message "Could not stop service; " -Logfile $$Logfile
                Exit
            }
            break;
        }
    }
    Get-Service $serviceName

}


Function Format-Date {
    <#
    .SYNOPSIS
    This function a dateformat

    .DESCRIPTION
    This function creates a dateformat to append to files or folders that looks like the following (2018-04-04_165004)

    .EXAMPLE
    $dateFormat = Format-Date
    #>
    return (Get-Date -Format 'yyyy-MM-dd_HHmmss')
}


Function Check-BackupRootDir {
    <#
    .SYNOPSIS
    This function checks to see if the Backup Root folder exists and if it doesn't it creates it

    .DESCRIPTION
    This function checks to see if the Backup Root folder exists and if it doesn't it creates it based on the input of the drive letter

    .PARAMETER DriveLetter
    Specifies the logging level

    .EXAMPLE
    Check-BackupRootDir -DriveLetter $DriveLetter

    #>
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $DriveLetter
    )
    
    $backupFldr = "vPostgres-Backup"
    $backupRoot = Join-Path $DriveLetter $backupFldr
    Write-Host "Backup Root: " $backupRoot
    If(!(Test-Path $backupRoot)) {
        Write-Host "Backup Root does not exist, creating it now" -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $backupRoot
    }
    Else {
        Write-Host "Backup Root does exist"
        $backupRoot = Get-ChildItem -Path $driveLetter | Where {$_.Name -match $backupFldr} | Select FullName
        return $backupRoot
    }

}


Function Create-DailyBackupDir {
    <#
    .SYNOPSIS
    This function creates the daily backup folder

    .DESCRIPTION
    This function takes the backup root drive as an impurt parameter and uses the Format-Date function to get the current date timestamp.
    Then uses this information along with the word DailyBackup to create the daily backup folder.

    .PARAMETER BackupRootDir
    Specifies the drive and root folder for backups

    .EXAMPLE
    Create-DailyBackupDir -BackupRootDir $backupRootDir
    #>
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $BackupRootDir,

    [Parameter(Mandatory=$True)]
    [string]
    $DateFormat
    )

    $folderName = "DailyBackup$DateFormat"
    $fullPath = Join-Path $BackupRootDir -ChildPath $folderName
    New-Item -ItemType Directory -Force -Path $fullPath
    
}


Function Backup-vPostgreSQL {
    <#
    .SYNOPSIS
    This function will backup a PostgreSQL database

    .DESCRIPTION
    This function will backup the SRM vPostgreSQL database and store it on in a folder you specify

    .PARAMETER BackupCommand
    Specifies the location of the backup executable

    .PARAMETER DatabaseUser
    Specifies the that has access to the SRM DB

    .PARAMETER DatabaseName
    Specifies the SRM database to backup

    .PARAMETER DailyBackupFolder
    Specifies the daily folder for the backups

    .PARAMETER DailyBackupFolder
    Specifies the port for the database if one is not supplied it will default to 5678

    .EXAMPLE
    Backup-vPostgreSQL -BackupCommand $backupExe -DatabaseUser $dbUser -DatabaseName $srmDB -DailyBackupFolder $dailyBackupFolder

    .EXAMPLE
    Backup-vPostgreSQL -BackupCommand $backupExe -DatabaseUser $dbUser -DatabaseName $srmDB -DailyBackupFolder $dailyBackupFolder -Port 1234
    #>

    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [string]
    $BackupCommand,

    [Parameter(Mandatory=$True)]
    [string]
    $DatabaseUser,

    [Parameter(Mandatory=$True)]
    [string]
    $DatabaseName,

    [Parameter(Mandatory=$True)]
    [string]
    $DailyBackupFolder,

    [Parameter(Mandatory=$False)]
    [string]
    $Port = 5678,

    [Parameter(Mandatory=$False)]
    [string]
    $Logfile
    )

    $bakupFile = "Daily-SRM-Backup"
    $backupPath = Join-path $DailyBackupFolder -childPath $bakupFile
    Write-Log -Level INFO -Message "Backup File Name: $backupPath" -Logfile $Logfile
    Write-Host "Backup File Name: " $backupPath -ForegroundColor Yellow

    Try {
    Start-Process -FilePath $BackupCommand -ArgumentList "-Fc", "-p $Port", "-d $DatabaseName", "-U $DatabaseUser", "-f $backupPath" -Wait -NoNewWindow
    }

    Catch {
        Write-host "Check the following error: " $Error
    }
}

 Function Get-FolderSize {
    <#
    .SYNOPSIS
    This function gets the size of a folder

    .DESCRIPTION
    This function gets the size of a folder for the passed in path

    .PARAMETER FolderPath
    Specifies the folder to report on

    .EXAMPLE
    Get-FolderSize -FolderPath "E:\vPostgres-Backup\DailyBackup2018-04-05_202545"
    #>

    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $FolderPath
    )

    $folderSize = Get-ChildItem -Path $FolderPath -Recurse | Measure-Object -Sum length
   
    If(($folderSize.Sum -ge 1073741824)) {
       $size = [Math]::Round($folderSize.Sum / 1GB, 2) 
       return $size
    }

    If(($folderSize.Sum -le 1024)) { 
       $size = [Math]::Round($folderSize.Sum / 1KB, 2)
       return $size
    }

    Else {
         $size = [Math]::Round($folderSize.Sum / 1MB, 2)
         return $size
    }

 }

 Function Remove-OldBackup {
    <#
    .SYNOPSIS
    This function deletes an old backup folder including the backup file

    .DESCRIPTION
    This function deletes a backup folder and file who has a creation date is of over 7 days 

    .PARAMETER BackupRoot
    Specifies the root path for backups

    .EXAMPLE
    Remove-OldBackup -BackupRoot "E:\vPostgres-Backup"
    #>

    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $BackupRoot,

    [Parameter(Mandatory=$false)]
    [String]
    $ExpireDate,

    [Parameter(Mandatory=$False)]
    [string]
    $Logfile
    )

    $ExpirationDate = (Get-Date).AddDays(-$ExpireDate);
    #$backupFolders = Get-ChildItem -Path $BackupRoot -Recurse | where {$_.CreationTime -lt $ExpirationDate} | Remove-Item -Force -Recurse
    $backupFolders = Get-ChildItem -Path $BackupRoot -Recurse | where {$_.CreationTime -lt $ExpirationDate}
    if ($backupFolders) {
        $backupFolders | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        Write-Log -Level WARNING -Message "Removed " $backupFolders.FullName -Logfile $Logfile
    }
    else {
        Write-Log -Level INFO -Message "No backup folder to remove " -Logfile $Logfile
    }
}

Function Check-AvailableBackupSpace {
    <#
    .SYNOPSIS
    This function checks to see if there is enough room to perform a backup

    .DESCRIPTION
    This function checks to see if there is enough room to perform a backup. It takes in 3 parameters (Free disk space, size of last backup, if it exists, and Overhead)

    .PARAMETER LastBackupSize
    Specifies the size of the last backup, set to 0 if there are no backups

    .PARAMETER FreeSpace
    Specifies the available free space on the drive where the backup will be placed

    .PARAMETER FreeSpace
    Specifies the amount of overhead you wish to add as a whole number

    .EXAMPLE
    Check-AvailableBackupSpace -LastBackupSize 0.5 -FreeSpace 9.1 -Overhead 10
    #>
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [Float]
    $LastBackupSize,

    [Parameter(Mandatory=$True)]
    [FLoat]
    $FreeSpace,

    [Parameter(Mandatory=$False)]
    [Float]
    $Overhead = 10
    )
    

    $overHeadPercentage = (($Overhead / 100) * $LastBackupSize)
    $spaceForNewBackup = $FreeSpace - $LastBackupSize
    Write-Host "Space: " $spaceForNewBackup
    $overheadRequired = $LastBackupSize * $overHeadPercentage
    Write-Host "Overhead Req: " $overheadRequired
    $SpaceWithOverhead = $LastBackupSize + $overheadRequired
    Write-Host "Space With Overhead: " $SpaceWithOverhead

    If ($spaceForNewBackup -ge $SpaceWithOverhead) {
        return $True
    }
    Else {
        return $False
    }
}

Function Archive-SrmDbBackup {
    <#
    .SYNOPSIS
    This function Copies the backup folder and it's contents to a UNC Share

    .DESCRIPTION
    This function Copies the backup folder and it's contents to a UNC Share specified by the input argument

    .PARAMETER DailyBackupFolder
    Specifies the daily backup folder

    .PARAMETER DestinationFolder
    Specifies the share the the folder will be copied to

    .EXAMPLE
    Archive-SrmDbBackup -DailyBackupFolder "E:\vPostgres-Backup\DailyBackup2018-04-11_164325" -DestinationFolder "\\192.168.1.200\SRM-Backups"
    #>
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True)]
    [String]
    $DailyBackupFolder,

    [Parameter(Mandatory=$True)]
    [string]
    $DestinationFolder
    )
    Try {
        Copy-Item $DailyBackupFolder -Destination $DestinationFolder -Recurse -Force
    }
    Catch {
        Write-Host "Could not copy File to share"
    }
}
