-- =====================================================================================
-- Quick Test: Pure Storage Snapshot via DatabaseBackup.sql
-- =====================================================================================
-- This script tests the specific scenario that was failing with HTTP 400 error
-- Run this to validate the fixes to the JSON payload construction

PRINT 'Testing Pure Storage Snapshot Integration via DatabaseBackup.sql';
PRINT 'Database: TPCC-4T';
PRINT 'Array: https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44';
PRINT 'Protection Group: aen-sql-25-a-pg';
PRINT '=======================================================================';

-- First test with Execute = 'N' to see the generated commands
PRINT '';
PRINT '1. DRY RUN TEST (Execute = N) - Check command generation:';
PRINT '-----------------------------------------------------------------------';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'TPCC-4T',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
        @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
        @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
        @PureStorageReplicateNow = 'N',
        @Directory = 'C:\Backups\',
        @Description = 'Unit Test - Dry Run',
        @Execute = 'N';
    
    PRINT 'DRY RUN: SUCCESS - No errors in command generation';
END TRY
BEGIN CATCH
    PRINT 'DRY RUN: FAILED - Error: ' + ERROR_MESSAGE();
END CATCH

PRINT '';
PRINT '2. LIVE TEST (Execute = Y) - Actual snapshot creation:';
PRINT '-----------------------------------------------------------------------';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'TPCC-4T',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
        @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
        @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
        @PureStorageReplicateNow = 'Y',
        @Directory = 'C:\Backups\',
        @Description = 'Unit Test - Live Run',
        @LogToTable = 'Y',
        @Execute = 'Y';
    
    PRINT 'LIVE TEST: SUCCESS - Snapshot backup completed';
END TRY
BEGIN CATCH
    PRINT 'LIVE TEST: FAILED - Error: ' + ERROR_MESSAGE();
    
    -- If the error is still HTTP 400, show detailed debugging info
    IF ERROR_MESSAGE() LIKE '%400%'
    BEGIN
        PRINT '';
        PRINT 'HTTP 400 Error detected. This indicates a problem with the JSON payload.';
        PRINT 'The JSON payload construction in DatabaseBackup.sql may still need adjustment.';
        PRINT 'Check the dynamic SQL output for malformed JSON.';
    END
END CATCH

PRINT '';
PRINT '=======================================================================';
PRINT 'Test completed at: ' + CONVERT(NVARCHAR, SYSDATETIME(), 121);

-- Check if any backup files were created
IF EXISTS (SELECT * FROM sys.backup_devices WHERE name LIKE '%TPCC-4T%' OR physical_name LIKE '%TPCC-4T%')
BEGIN
    PRINT 'Backup device entries found - check backup history';
END

-- Show recent backup history for the test database
IF EXISTS (SELECT * FROM msdb.dbo.backupset WHERE database_name = 'TPCC-4T' AND backup_start_date >= DATEADD(MINUTE, -10, GETDATE()))
BEGIN
    PRINT '';
    PRINT 'Recent backup history for TPCC-4T:';
    SELECT 
        backup_start_date,
        type,
        media_description,
        backup_size,
        compressed_backup_size,
        first_lsn,
        last_lsn
    FROM msdb.dbo.backupset 
    WHERE database_name = 'TPCC-4T' 
    AND backup_start_date >= DATEADD(MINUTE, -10, GETDATE())
    ORDER BY backup_start_date DESC;
END
