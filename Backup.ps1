param(
    [parameter(HelpMessage="Specific folder path to backup")][string]$TargetFolder,
    [parameter(HelpMessage="Run full backup rathan differential")][switch]$FullBackup,
    [parameter(HelpMessage="Use faster compression, results in larger backup file")][switch]$Quick,
    [parameter(HelpMessage="List files only, without backing them up")][switch]$Audit
    )

#Create config file if it doesn't already exist

if(!(Test-Path "$PSScriptRoot\BackupLog.txt")){
    New-Item -Path "$PSScriptRoot\BackupLog.txt" -ErrorAction Stop | Out-Null
}

#Error handling function
function Error {
    param (
        [parameter(Mandatory)][string]$Message,
        [parameter()][switch]$Fatal
    )
    $ErrorDate = get-date -Format "yyyy-MM-dd"
    $ErrorTime = get-date -Format "HH:mm:ss"
    if($Fatal){
        Write-Host "`n"
        Write-Host "$ErrorDate - $ErrorTime Fatal Error! $Message"
        echo "$ErrorDate + $ErrorTime + Fatal Error! $Message - Exit" | Out-File -FilePath "$script:PSScriptRoot\BackupLog.txt" -Append
        Write-Host "`n"
        start-sleep 10
        exit
    } else {
        Write-Host "`n"
        Write-Host "$ErrorDate - $ErrorTime Error! $Message"
        $ErrorResponse = Read-Host "Continue anyway? y/[n]"
        if($ErrorResponse -eq "y"){
            echo "$ErrorDate - $ErrorTime - Error $Message - Continue" | Out-File -FilePath "$script:PSScriptRoot\BackupLog.txt" -Append
            return "Continue"
        } else {
            echo "$ErrorDate - $ErrorTime - Error $Message - Exit" | Out-File -FilePath "$script:PSScriptRoot\BackupLog.txt" -Append
            exit
        }
    }
    
}
#Script start
$Date = get-date -Format "yyyy-MM-dd"
$StartTime = get-date -Format "HH:mm:ss"
$FileTime = get-date -Format "HHmm"
echo "$Date - $StartTime - Script Start" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
if (Get-Module -ListAvailable -Name "7Zip4Powershell") {
    Import-Module "7Zip4Powershell" 
} 
else {
    try {
        Write-Host "Installing required module 7Zip4Powershell"
        Install-Module -Name "7Zip4Powershell" -Scope CurrentUser
    }
    catch {
        Error -Message "Unable to install required module 7Zip4Powershell" -Fatal
    }
    echo "$Date - $StartTime - Installed 7Zip4Powershell" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
}
#Read and check config file
try {
    Invoke-Expression (get-content "$PSScriptRoot\BackupConfig.txt" | out-string)
}
catch {
    Error -Message "Unable to read config file - $PSScriptRoot\BackupConfig.txt - Make sure it is formatted correctly and not missing any commas are quote marks" -Fatal
}
if($Locations.Length -eq 0){Error -Message "`$Locations no folders selected to backup" -Fatal}
if($BackupFolders.Length -eq 0){Error -Message "`$Locations no folders selected to store backup" -Fatal}

#Check target files and backup locations exist
$FolderCount = $Locations.length
$Locations | ForEach-Object {
    if(!(Test-Path $_)){
        $FolderCount = $FolderCount - 1
        if($FolderCount -eq 0){
        Error -Message "Unable to find $_ - No other valid folders to backup have been selected!" -Fatal
        } else {
            Error -Message "Unable to find $_"
        }
    }
}
$FolderCount = $BackupFolders.length
$BackupFolders | ForEach-Object {
    if(!(Test-Path $_)){
        $FolderCount = $FolderCount - 1
        if($FolderCount -eq 0){
        Error -Message "Unable to find $_ - No other valid locations to store backups have been selected!" -Fatal
        } else {
            Error -Message "Unable to find $_"
        }
    }
}
$ScriptPath = $PSScriptRoot
#Options
#Allow user to specifiy full backup from terminal
if($FullBackup){
    $DifferentialBackup = $false
} else {
    $DifferentialBackup = $true
}
#Allow to specify quick, using faster compression. Defaults to maximum compression
if($Quick){
    $Speed = "Fast"
    $SpeedType = "Max speed"
} else {
    $Speed = "Ultra"
    $SpeedType = "Max compression"
}
#Allow specific folder to be backed up, rather than the folders specified in the config
if($TargetFolder){
    $TargetFolder = $TargetFolder.ToString()
    $Locations = $TargetFolder
    $CustomName = (Split-Path -Path $TargetFolder -Leaf).Replace(" ","")
    $Target = $TargetFolder
}else{
    $CustomName = ""
    $Target = "Standard (From config)"
}
if($Audit){
    $Type = "Audit"
} elseif($DifferentialBackup -and (Test-Path "$ScriptPath\$FullFileList")) {
    $Type = "Differential"
} else {
    $Type = "Full"
}
if(!(Test-Path "$ScriptPath\$FullFileList")){
    echo "$Date - $StartTime - $ScriptPath\$FullFileList does not exist, setting backup type to Full" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
    Write-Host "$ScriptPath\$FullFileList does not exist, setting backup type to Full"
    $Type = "Full"
    $DifferentialBackup = $false
}

echo "$Date - $StartTime - Type: $Type - Targeting: $Target - Compression: $SpeedType" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append

#setup names and locations
$FullFileList = "$($CustomName)BackupFiles.csv"
$DifferFileList = "$($CustomName)BackupFilesDiffer.csv"

#Setup hash table from previous results
$OldFiles = @{}
if((Test-Path "$ScriptPath\$FullFileList") -and $DifferentialBackup){
    $OldFilesCSV = Import-Csv -Path "$ScriptPath\$FullFileList" -Delimiter ">"
    $OldFilesCSV | ForEach-Object {
        $OldFiles[$_.Path] = $_.Hash
    }
}
#Create new file lists (overwriting the old ones)
echo "Path>Size(MB)>Hash" | Out-File "$ScriptPath\Temp$FullFileList"
echo "Path>Size(MB)>Hash" | Out-File "$ScriptPath\$DifferFileList"
$Locations | ForEach-Object {
    Write-Host "Checking $_"
    #check if a backup exclusion file exists and read it
    if(Test-Path -Path "$($_)\BackupExclude.txt"){
        try {
            $Exclude = Invoke-Expression (get-content "$($_)\BackupExclude.txt" | out-string)
        }
        catch {
            Error -Message "Unable to read config file - $PSScriptRoot\BackupConfig.txt - Make sure it is formatted correctly and not missing any commas are quote marks - Continue without exclusions?"
            $Exclude = @()
        } 
    } else {
        $Exclude = @()
    }
    #Iterate through directory looking for subfolders
    $Folders = @($_)
    $NewCount = 1
    while ($NewCount -ne 0) { #Keep looping until no new subfolders are found
        $Folders | ForEach-Object{
            $NewCount = 0
            Get-ChildItem -Path $_ -Directory | Where-Object {$Folders -notcontains $_.FullName -and $Exclude -notcontains $_.FullName} | ForEach-Object{$Folders = $Folders + $_.FullName; $NewCount = $NewCount + 1}
        }
    }
    #Now all subfolders have been found, get details for each file
    $Folders | ForEach-Object { Get-ChildItem -Path $_ -File } | Get-FileHash -Algorithm md5 | ForEach-Object {
        if($_.Path -ne "$ScriptPath\$FullFileList" -and $_.Path -ne "$ScriptPath\$DifferFileList"){
            $Hash = $_.Hash
            $Path = $_.Path
            $Size = (Get-Item -Path $Path).length
            $Size = [math]::Round(((Get-Item -Path $Path).length/1000000),3)
            #For all Files, record in the full file list
            try {
                echo "$Path>$Size>$Hash" | Out-File "$ScriptPath\Temp$FullFileList" -Append
            }
            catch {
                Error -Message "Unable to write to $ScriptPath\$FullFileList - Make sure it isn't open somewhere else"
            }
            #For files that are new or have changed record in the differ list
            if($OldFiles[$Path].length -le 1 -or $OldFiles[$Path] -ne $Hash){
                try {
                    echo "$Path>$Size>$Hash" | Out-File "$ScriptPath\$DifferFileList" -Append
                }
                catch {
                    Error -Message "Unable to write to $ScriptPath\$DifferFileList - Make sure it isn't open somewhere else"
                }
            }
        }
    }
}
if($Audit){
    $Time = get-date -Format "HH:mm:ss"
    echo "$Date - $Time - Type: $Type - Targeting: $Target - Compression: $SpeedType" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
    exit
}

#Create the staging folder (if it doesn't exist already)
try {
    New-Item -Path "$StagingFolder\Backup" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
}
catch {
    Error -Message "Unable to create staging folder $StagingFolder\Backup" -Fatal
}
if($DifferentialBackup){
    $BackupFiles = Import-Csv -Path "$ScriptPath\$DifferFileList" -Delimiter ">"
    Copy-Item -Path "$ScriptPath\$DifferFileList" -Destination "$StagingFolder\Backup" -Force
} else {
    $BackupFiles = Import-Csv -Path "$ScriptPath\$FullFileList" -Delimiter ">"
    Copy-Item -Path "$ScriptPath\$FullFileList" -Destination "$StagingFolder\Backup" -Force
}

$TotalFiles = $BackupFiles.length
Write-Host "Copying $TotalFiles files to staging folder..."
$CopyTime = get-date -Format "HH:mm:ss"
echo "$Date - $CopyTime - File copy starting" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
$FileCount = 0
$FailFiles = @()
$BackupFiles | ForEach-Object{
    #echo "$($_.path)"
    $FileCount = $FileCount + 1
    if($FileCount % 100 -eq 0){
        Write-Host "$FileCount/$TotalFiles"
    }
    $FolderPath = Split-Path -Path $_.path -Parent
    $FolderPath = $FolderPath.Replace(":","")
    New-Item -Path "$StagingFolder\Backup\$FolderPath" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    try {
        Copy-Item -Path $_.path -Destination "$StagingFolder\Backup\$FolderPath" -Force -errorAction stop
    }
    catch {
        $FailFiles = $FailFiles + $_
    }  
}
if($FailFiles.Length -ne 0){
    if(!(Test-Path $ScriptPath\FailFiles.csv)){
        echo "Date>Time>Path" | Out-File "$ScriptPath\FailFiles.csv"
    }
    $FailFiles | ForEach-Object{
        echo "$Date>$CopyTime>$_" | Out-File "$ScriptPath\FailFiles.csv" -Append
    }
    Error -Message "Failed to copy $($FailFiles.Length) files to staging. See $ScriptPath\FailFiles.csv for list"
}
$FileCount = $FileCount - $FailFiles.Length
if($FileCount -eq 0){
    Write-Host "No files have changed"
    exit
}
$BackupName = "$($Date)-$($FileTime)-$($CustomName)$($Type)Backup"
if(Test-Path "$StagingFolder\Backup"){
    if(Test-Path "$StagingFolder\Backup\$BackupName.zip"){
        Write-Host "There is an old backup... somehow"
        Remove-Item -Path "$StagingFolder\Backup\$BackupName.zip"
    }
    Write-Host "Starting compression..."
    $CompressionTime = get-date -Format "HH:mm:ss"
    echo "$Date - $CompressionTime - File compression starting" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
    Compress-7Zip -ArchiveFileName "$BackupName.zip" -Path "$StagingFolder\Backup" -OutputPath "$StagingFolder" -Format Zip -CompressionLevel $Speed
} else {
    Write-Host "No files have changed since last backup"
    echo "$Date - $CompressionTime - No files have changed" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
    exit
}
$BackupSize = [math]::Round((((get-item -Path "$StagingFolder\$BackupName.zip").length)/1000000000),3)
$FinishTime = get-date -Format "HH:mm:ss"
echo "$Date - $FinishTime - Compression finished - $FileCount files - $BackupSize GB - $BackupName.zip" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
$BackupFolders | ForEach-Object{
    try {
        New-Item -Path "$_" -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Error -Message "Unable to create backup folder $_" -Fatal
    }
    Write-Host "Copying backup to $_"
    try {
        Copy-Item -Path "$StagingFolder\$BackupName.zip" -Destination $_ -ErrorAction Stop
    }
    catch {
        Error -Message "Unable to copy files to backup folder $_"
    }
    $MovedTime = get-date -Format "HH:mm:ss"
    if(!(Test-Path "$_\BackupLog.txt")){
        New-Item -Path "$_\BackupLog.txt" -ErrorAction SilentlyContinue | Out-Null
    }
    echo "$Date - $MovedTime - $Type - $FileCount files - $BackupSize GB - $BackupName.zip" | Tee-Object -FilePath "$_\BackupLog.txt" -Append
    echo "$Date - $MovedTime - Move to $_ completed" | Out-File -FilePath "$PSScriptRoot\BackupLog.txt" -Append
}
Move-Item -Path "$ScriptPath\Temp$FullFileList" -Destination "$PSScriptRoot\$FullFileList" -Force
if(!$DifferentialBackup){Copy-Item -Path "$ScriptPath\$FullFileList" -Destination "$PSScriptRoot\LastFullBackupFiles.csv" -Force}
Remove-Item -Path "$StagingFolder" -Recurse #clear the staging folder
Remove-Item -Path "$ScriptPath\$DifferFileList" #clear the differ file
