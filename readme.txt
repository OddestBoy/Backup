Usage:
-Put Backup.ps1 and BackupConfig.txt in a folder together
-Edit BackupConfig.txt with the folders you want to back up, where you want the backups to be stored, and the staging folder where they will be placed temporarily during processing.

Subfolders can be excluded from backups. If you want to back up all of \Documents except a subfolder \Documents\ExcludedFolder (maybe the files it contains are massive and not important), place BackupExclude.txt in \Documents listing any sub folders you don't want backing up.

Logs are stored in BackupLog.txt, in the folder the script is in

I recommend running the script with a scheduled task.

By default, if there is no existing file list (ie on first run), a full backup will be taken, of all non-excluded files in the specified folders. On subsequent runs, only differential backups will be taken (so only files that have changed since they were last backed up)

The script can be called from the command line, with any of the following options:
-TargetFolder : A specific folder to backup, rather than using the folders listed in BackupConfig.txt
-TargetBackup : A specific folder to move the backup to, rather than the destinations from BackupConfig.txt
-FullBackup : Force a full backup
-Quick : Use quicker but less space-saving compression
-Audit : Just build file list, without backing up files
