EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T', --this is a 4TB database
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.46',
    @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
    @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
    @PureStorageReplicateNow = 'Y',
    @Directory = 'C:\Backups\',
    @LogToTable = 'Y'

SELECT TOP 1
    ID, DatabaseName, CommandType, Command, 
    StartTime, EndTime, ErrorNumber, ErrorMessage
FROM dbo.CommandLog
ORDER BY StartTime DESC;


-- Multiple selected databases with one snapshot
EXEC dbo.DatabaseBackup 
  @Databases = 'TPCC-4T, TPCC500G',
  @BackupType = 'SNAPSHOT',
  @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
  @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.46',
  @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
  @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
  @SnapshotMode = 'GROUP',
  @Directory = 'C:\Backups',
  @LogToTable = 'Y'

SELECT TOP 10
    ID, DatabaseName, CommandType, Command, 
    StartTime, EndTime, ErrorNumber, ErrorMessage
FROM dbo.CommandLog
ORDER BY StartTime DESC;


-- All user databases with one snapshot
EXEC dbo.DatabaseBackup 
  @Databases = 'USER_DATABASES',
  @BackupType = 'SNAPSHOT',
  @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
  @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.46',
  @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
  @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
  @SnapshotMode = 'SERVER',
  @Directory = 'C:\Backups',
  @LogToTable = 'Y'

-- To see all snapshot-related commands (suspend, backup, unsuspend, Pure Storage API calls)
SELECT TOP 10 
    ID, DatabaseName, CommandType, Command, 
    StartTime, EndTime, ErrorNumber, ErrorMessage
FROM dbo.CommandLog
ORDER BY StartTime DESC;