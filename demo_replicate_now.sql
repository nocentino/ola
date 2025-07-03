-- =====================================================================================
-- Pure Storage Snapshot with Replication Control Demo
-- =====================================================================================
-- This script demonstrates the new @PureStorageReplicateNow parameter that allows
-- control over immediate replication of snapshots to secondary arrays.
--
-- @PureStorageReplicateNow = 'N' (default) - Snapshot only, no immediate replication  
-- @PureStorageReplicateNow = 'Y' - Snapshot with immediate replication
-- =====================================================================================

PRINT 'Pure Storage Snapshot Replication Control Demo';
PRINT '==============================================';
PRINT '';

-- =====================================================================================
-- Example 1: Standard Snapshot (No Immediate Replication)
-- =====================================================================================
PRINT '1. Standard Snapshot (No Immediate Replication):';
PRINT '   @PureStorageReplicateNow = ''N'' (default)';
PRINT '   Creates snapshot locally only, replication follows array schedule';
PRINT '';

/*
EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
    @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
    @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
    @PureStorageReplicateNow = 'N',
    @Directory = 'C:\Backups\',
    @Description = 'Standard snapshot - no immediate replication',
    @LogToTable = 'Y';
*/

-- =====================================================================================
-- Example 2: Snapshot with Immediate Replication
-- =====================================================================================
PRINT '2. Snapshot with Immediate Replication:';
PRINT '   @PureStorageReplicateNow = ''Y''';
PRINT '   Creates snapshot and immediately replicates to secondary array';
PRINT '';

/*
EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
    @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
    @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
    @PureStorageReplicateNow = 'Y',
    @Directory = 'C:\Backups\',
    @Description = 'Snapshot with immediate replication',
    @LogToTable = 'Y';
*/

-- =====================================================================================
-- Use Cases for Each Option
-- =====================================================================================
PRINT 'USE CASES:';
PRINT '';
PRINT '@PureStorageReplicateNow = ''N'' (Default):';
PRINT '  • Regular scheduled backups';
PRINT '  • Performance-sensitive environments';
PRINT '  • When replication schedule is managed separately';
PRINT '  • Reduces backup window time';
PRINT '';
PRINT '@PureStorageReplicateNow = ''Y'':';
PRINT '  • Critical database snapshots requiring immediate DR protection';
PRINT '  • Before major maintenance or upgrades';
PRINT '  • One-time snapshots that need immediate offsite protection';
PRINT '  • Compliance requirements for immediate replication';
PRINT '';

-- =====================================================================================
-- Parameter Validation Examples
-- =====================================================================================
PRINT 'PARAMETER VALIDATION:';
PRINT '';

-- This will fail validation - invalid value
PRINT 'Example of invalid parameter value (will fail validation):';
/*
EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44',
    @PureStorageAPIToken = '3b078aa4-94a8-68da-8e7b-04aec357f678',
    @PureStorageProtectionGroup = 'aen-sql-25-a-pg',
    @PureStorageReplicateNow = 'INVALID',  -- This will cause validation error
    @Directory = 'C:\Backups\',
    @Execute = 'N';
*/

-- This will fail validation - parameter used with wrong backup software
PRINT 'Example of parameter used with wrong backup software (will fail validation):';
/*
EXEC dbo.DatabaseBackup 
    @Databases = 'TPCC-4T',
    @BackupType = 'FULL',
    @BackupSoftware = 'LITESPEED',  -- Wrong backup software
    @PureStorageReplicateNow = 'Y',  -- This will cause validation error
    @Directory = 'C:\Backups\',
    @Execute = 'N';
*/

PRINT '';
PRINT 'Demo complete. Uncomment the EXEC statements above to test live functionality.';
PRINT '=====================================================================================';
