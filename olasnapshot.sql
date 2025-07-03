EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
    @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
    @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
    @PureStorageReplicateNow = 'Y',
    @Directory = 'C:\Backups\',
    @LogToTable = 'Y'

