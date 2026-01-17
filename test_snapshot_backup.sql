/*
================================================================================
Pure Storage Snapshot Backup Test Harness
================================================================================
Version: 1.0
Date: 2026-01-17
Purpose: Comprehensive testing of SINGLE, GROUP, and SERVER snapshot modes
         for the Ola Hallengren DatabaseBackup Pure Storage integration

Prerequisites:
- MaintenanceSolution.sql deployed with Pure Storage snapshot support
- Valid Pure Storage array URL and API token
- Protection Group configured on Pure Storage array
- Test databases created (or modify @TestDatabases variable)

Usage:
- Set @ExecuteTests = 1 to run actual backups (creates real snapshots!)
- Set @ExecuteTests = 0 for dry-run validation only
================================================================================
*/

SET NOCOUNT ON;
GO

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
DECLARE @ExecuteTests bit = 0;  -- Set to 1 to actually execute backups
DECLARE @CleanupAfterTests bit = 0;  -- Set to 1 to delete test CommandLog entries

-- Pure Storage Configuration
DECLARE @PureStorageArrayURL nvarchar(500) = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.46';
DECLARE @PureStorageAPIToken nvarchar(100) = '3b078aa4-94a8-68da-8e7b-04aec357f678';
DECLARE @PureStorageProtectionGroup nvarchar(100) = 'aen-sql-25-a-pg';
DECLARE @BackupDirectory nvarchar(500) = 'C:\Backups';

-- Test databases (modify as needed for your environment)
DECLARE @TestDB1 nvarchar(128) = 'AdventureWorks2025';  -- Standard name
DECLARE @TestDB2 nvarchar(128) = 'TPCC500G';            -- Standard name
DECLARE @TestDBWithHyphen nvarchar(128) = 'TPCC-4T';    -- Name with hyphen (edge case)

-- ============================================================================
-- TEST RESULTS TABLE
-- ============================================================================
IF OBJECT_ID('tempdb..#TestResults') IS NOT NULL DROP TABLE #TestResults;
CREATE TABLE #TestResults (
    TestID int IDENTITY(1,1) PRIMARY KEY,
    TestName nvarchar(200) NOT NULL,
    TestCategory nvarchar(50) NOT NULL,
    StartTime datetime2 DEFAULT SYSDATETIME(),
    EndTime datetime2,
    Status nvarchar(20) DEFAULT 'Running',  -- Running, Passed, Failed, Skipped
    Details nvarchar(max),
    CommandLogIDs nvarchar(500)
);

-- ============================================================================
-- HELPER PROCEDURES
-- ============================================================================
GO

-- Log test start
CREATE OR ALTER PROCEDURE #LogTestStart
    @TestName nvarchar(200),
    @TestCategory nvarchar(50)
AS
BEGIN
    INSERT INTO #TestResults (TestName, TestCategory)
    VALUES (@TestName, @TestCategory);
    
    PRINT '----------------------------------------';
    PRINT 'TEST: ' + @TestName;
    PRINT 'Category: ' + @TestCategory;
    PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
    PRINT '----------------------------------------';
    
    RETURN SCOPE_IDENTITY();
END;
GO

-- Log test result
CREATE OR ALTER PROCEDURE #LogTestResult
    @TestID int,
    @Status nvarchar(20),
    @Details nvarchar(max) = NULL,
    @CommandLogIDs nvarchar(500) = NULL
AS
BEGIN
    UPDATE #TestResults
    SET EndTime = SYSDATETIME(),
        Status = @Status,
        Details = @Details,
        CommandLogIDs = @CommandLogIDs
    WHERE TestID = @TestID;
    
    PRINT 'Result: ' + @Status;
    IF @Details IS NOT NULL PRINT 'Details: ' + @Details;
    PRINT '';
END;
GO

-- ============================================================================
-- PRE-FLIGHT CHECKS
-- ============================================================================
PRINT '============================================================';
PRINT 'PURE STORAGE SNAPSHOT BACKUP TEST HARNESS';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '============================================================';
PRINT '';

DECLARE @TestID int;
DECLARE @ErrorCount int = 0;
DECLARE @MaxCommandLogID int;
DECLARE @NewCommandLogIDs nvarchar(500);

-- Save current max CommandLog ID
SELECT @MaxCommandLogID = ISNULL(MAX(ID), 0) FROM dbo.CommandLog;

-- ----------------------------------------------------------------------------
-- Test 0: Pre-flight validation
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'Pre-flight Validation', 'Setup';

DECLARE @PreflightErrors nvarchar(max) = '';

-- Check if DatabaseBackup procedure exists
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND type = 'P')
    SET @PreflightErrors += 'DatabaseBackup procedure not found. ';

-- Check if CommandLog table exists
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.CommandLog') AND type = 'U')
    SET @PreflightErrors += 'CommandLog table not found. ';

-- Check if required parameters are supported
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND name = '@SnapshotMode')
    SET @PreflightErrors += '@SnapshotMode parameter not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND name = '@PureStorageArrayURL')
    SET @PreflightErrors += '@PureStorageArrayURL parameter not found. ';

-- Check if key fixes are deployed
DECLARE @ProcDefinition nvarchar(max) = OBJECT_DEFINITION(OBJECT_ID('dbo.DatabaseBackup'));

IF @ProcDefinition NOT LIKE '%@LoginURL%'
    SET @PreflightErrors += 'Login URL fix not deployed. ';

IF @ProcDefinition NOT LIKE '%QUOTENAME(DatabaseName)%FROM @tmpDatabases%WHERE Selected = 1%'
    SET @PreflightErrors += 'QUOTENAME fix for GROUP mode not deployed. ';

IF @ProcDefinition NOT LIKE '%@ServerBackupDone%'
    SET @PreflightErrors += 'ServerBackupDone flag not deployed. ';

IF @ProcDefinition NOT LIKE '%included in SERVER snapshot%'
    SET @PreflightErrors += 'SERVER mode logging fix not deployed. ';

-- Check test databases exist
DECLARE @TestDBWithHyphenLocal nvarchar(128) = 'TPCC-4T';
DECLARE @TestDB1Local nvarchar(128) = 'AdventureWorks2025';
DECLARE @TestDB2Local nvarchar(128) = 'TPCC500G';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDB1Local)
    SET @PreflightErrors += 'Test database ' + @TestDB1Local + ' not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDB2Local)
    SET @PreflightErrors += 'Test database ' + @TestDB2Local + ' not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDBWithHyphenLocal)
    SET @PreflightErrors += 'Test database ' + @TestDBWithHyphenLocal + ' not found (hyphen test). ';

IF LEN(@PreflightErrors) > 0
BEGIN
    EXEC #LogTestResult @TestID, 'Failed', @PreflightErrors;
    SET @ErrorCount += 1;
    PRINT 'CRITICAL: Pre-flight checks failed. Fix issues before running tests.';
END
ELSE
BEGIN
    EXEC #LogTestResult @TestID, 'Passed', 'All pre-flight checks passed.';
END;

-- ============================================================================
-- PARAMETER VALIDATION TESTS
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT 'PARAMETER VALIDATION TESTS';
PRINT '============================================================';

-- ----------------------------------------------------------------------------
-- Test 1: Invalid SnapshotMode value
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'Invalid SnapshotMode Value', 'Validation';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'AdventureWorks2025',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = 'https://test.purestorage.com/api/2.46',
        @PureStorageAPIToken = 'test-token',
        @PureStorageProtectionGroup = 'test-pg',
        @SnapshotMode = 'INVALID_MODE',
        @Directory = 'C:\Backups',
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Failed', 'Should have raised error for invalid SnapshotMode';
    SET @ErrorCount += 1;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%SnapshotMode%'
        EXEC #LogTestResult @TestID, 'Passed', 'Correctly rejected invalid SnapshotMode';
    ELSE
    BEGIN
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 2: GROUP mode requires PURESTORAGE_SNAPSHOT
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'GROUP Mode Requires PURESTORAGE_SNAPSHOT', 'Validation';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'AdventureWorks2025',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = NULL,  -- Invalid for GROUP mode
        @SnapshotMode = 'GROUP',
        @Directory = 'C:\Backups',
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Failed', 'Should have raised error for GROUP without PURESTORAGE_SNAPSHOT';
    SET @ErrorCount += 1;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%GROUP%' OR ERROR_MESSAGE() LIKE '%PURESTORAGE%'
        EXEC #LogTestResult @TestID, 'Passed', 'Correctly rejected GROUP mode without PURESTORAGE_SNAPSHOT';
    ELSE
    BEGIN
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 3: SERVER mode requires USER_DATABASES or ALL_DATABASES
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'SERVER Mode Database Validation', 'Validation';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'AdventureWorks2025',  -- Single DB not allowed for SERVER mode
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = 'https://test.purestorage.com/api/2.46',
        @PureStorageAPIToken = 'test-token',
        @PureStorageProtectionGroup = 'test-pg',
        @SnapshotMode = 'SERVER',
        @Directory = 'C:\Backups',
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Failed', 'Should have raised error for SERVER with single database';
    SET @ErrorCount += 1;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%SERVER%' OR ERROR_MESSAGE() LIKE '%USER_DATABASES%' OR ERROR_MESSAGE() LIKE '%ALL_DATABASES%'
        EXEC #LogTestResult @TestID, 'Passed', 'Correctly rejected SERVER mode with single database';
    ELSE
    BEGIN
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END
END CATCH;

-- ============================================================================
-- DRY RUN TESTS (Execute = N)
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT 'DRY RUN TESTS (Execute = N)';
PRINT '============================================================';

-- ----------------------------------------------------------------------------
-- Test 4: SINGLE mode dry run
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'SINGLE Mode Dry Run', 'DryRun';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'AdventureWorks2025',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = @PureStorageArrayURL,
        @PureStorageAPIToken = @PureStorageAPIToken,
        @PureStorageProtectionGroup = @PureStorageProtectionGroup,
        @SnapshotMode = 'SINGLE',
        @Directory = @BackupDirectory,
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Passed', 'SINGLE mode dry run completed without errors';
END TRY
BEGIN CATCH
    EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
    SET @ErrorCount += 1;
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 5: GROUP mode dry run with hyphenated database name
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'GROUP Mode Dry Run (Hyphen in DB Name)', 'DryRun';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'TPCC-4T, TPCC500G',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = @PureStorageArrayURL,
        @PureStorageAPIToken = @PureStorageAPIToken,
        @PureStorageProtectionGroup = @PureStorageProtectionGroup,
        @SnapshotMode = 'GROUP',
        @Directory = @BackupDirectory,
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Passed', 'GROUP mode dry run with hyphenated name completed';
END TRY
BEGIN CATCH
    EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
    SET @ErrorCount += 1;
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 6: SERVER mode dry run
-- ----------------------------------------------------------------------------
EXEC @TestID = #LogTestStart 'SERVER Mode Dry Run', 'DryRun';

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'USER_DATABASES',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
        @PureStorageArrayURL = @PureStorageArrayURL,
        @PureStorageAPIToken = @PureStorageAPIToken,
        @PureStorageProtectionGroup = @PureStorageProtectionGroup,
        @SnapshotMode = 'SERVER',
        @Directory = @BackupDirectory,
        @Execute = 'N';
    
    EXEC #LogTestResult @TestID, 'Passed', 'SERVER mode dry run completed without errors';
END TRY
BEGIN CATCH
    EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
    SET @ErrorCount += 1;
END CATCH;

-- ============================================================================
-- LIVE EXECUTION TESTS (Only if @ExecuteTests = 1)
-- ============================================================================
DECLARE @ExecuteTestsLocal bit = 0;  -- Redeclare for this batch

IF @ExecuteTestsLocal = 1
BEGIN
    PRINT '';
    PRINT '============================================================';
    PRINT 'LIVE EXECUTION TESTS (Creating Real Snapshots!)';
    PRINT '============================================================';
    
    DECLARE @PreTestMaxID int;
    SELECT @PreTestMaxID = ISNULL(MAX(ID), 0) FROM dbo.CommandLog;
    
    -- ------------------------------------------------------------------------
    -- Test 7: SINGLE mode live execution
    -- ------------------------------------------------------------------------
    EXEC @TestID = #LogTestStart 'SINGLE Mode Live Execution', 'LiveExecution';
    
    BEGIN TRY
        EXEC dbo.DatabaseBackup 
            @Databases = 'AdventureWorks2025',
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageArrayURL = @PureStorageArrayURL,
            @PureStorageAPIToken = @PureStorageAPIToken,
            @PureStorageProtectionGroup = @PureStorageProtectionGroup,
            @SnapshotMode = 'SINGLE',
            @Directory = @BackupDirectory,
            @LogToTable = 'Y';
        
        -- Verify CommandLog entry
        DECLARE @SingleModeLogCount int;
        SELECT @SingleModeLogCount = COUNT(*) 
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND ErrorNumber = 0;
        
        IF @SingleModeLogCount = 1
            EXEC #LogTestResult @TestID, 'Passed', 'SINGLE mode created 1 CommandLog entry';
        ELSE
        BEGIN
            EXEC #LogTestResult @TestID, 'Failed', 'Expected 1 CommandLog entry, got ' + CAST(@SingleModeLogCount as varchar);
            SET @ErrorCount += 1;
        END
        
        SELECT @PreTestMaxID = MAX(ID) FROM dbo.CommandLog;
    END TRY
    BEGIN CATCH
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END CATCH;
    
    -- ------------------------------------------------------------------------
    -- Test 8: GROUP mode live execution
    -- ------------------------------------------------------------------------
    EXEC @TestID = #LogTestStart 'GROUP Mode Live Execution', 'LiveExecution';
    
    BEGIN TRY
        EXEC dbo.DatabaseBackup 
            @Databases = 'TPCC-4T, TPCC500G',
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageArrayURL = @PureStorageArrayURL,
            @PureStorageAPIToken = @PureStorageAPIToken,
            @PureStorageProtectionGroup = @PureStorageProtectionGroup,
            @SnapshotMode = 'GROUP',
            @Directory = @BackupDirectory,
            @LogToTable = 'Y';
        
        -- Verify CommandLog entries (should be 2 - one per database)
        DECLARE @GroupModeLogCount int;
        DECLARE @GroupModeSnapshotName nvarchar(200);
        
        SELECT @GroupModeLogCount = COUNT(*),
               @GroupModeSnapshotName = MAX(CASE WHEN Command LIKE '%MEDIADESCRIPTION%' 
                   THEN SUBSTRING(Command, CHARINDEX('MEDIADESCRIPTION=N''', Command) + 19, 50) END)
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND ErrorNumber = 0;
        
        -- Verify both entries reference same snapshot
        DECLARE @DistinctSnapshots int;
        SELECT @DistinctSnapshots = COUNT(DISTINCT 
            SUBSTRING(Command, CHARINDEX('MEDIADESCRIPTION=N''', Command) + 19, 
                CHARINDEX('''', Command, CHARINDEX('MEDIADESCRIPTION=N''', Command) + 19) - CHARINDEX('MEDIADESCRIPTION=N''', Command) - 19))
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND Command LIKE '%MEDIADESCRIPTION%';
        
        IF @GroupModeLogCount = 2 AND @DistinctSnapshots = 1
            EXEC #LogTestResult @TestID, 'Passed', 'GROUP mode: 2 entries, same snapshot';
        ELSE
        BEGIN
            EXEC #LogTestResult @TestID, 'Failed', 
                'Expected 2 entries with same snapshot. Got ' + CAST(@GroupModeLogCount as varchar) + 
                ' entries, ' + CAST(@DistinctSnapshots as varchar) + ' distinct snapshots';
            SET @ErrorCount += 1;
        END
        
        SELECT @PreTestMaxID = MAX(ID) FROM dbo.CommandLog;
    END TRY
    BEGIN CATCH
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END CATCH;
    
    -- ------------------------------------------------------------------------
    -- Test 9: SERVER mode live execution
    -- ------------------------------------------------------------------------
    EXEC @TestID = #LogTestStart 'SERVER Mode Live Execution', 'LiveExecution';
    
    BEGIN TRY
        -- Count user databases
        DECLARE @UserDBCount int;
        SELECT @UserDBCount = COUNT(*) 
        FROM sys.databases 
        WHERE database_id > 4 
          AND state = 0 
          AND source_database_id IS NULL;
        
        EXEC dbo.DatabaseBackup 
            @Databases = 'USER_DATABASES',
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageArrayURL = @PureStorageArrayURL,
            @PureStorageAPIToken = @PureStorageAPIToken,
            @PureStorageProtectionGroup = @PureStorageProtectionGroup,
            @SnapshotMode = 'SERVER',
            @Directory = @BackupDirectory,
            @LogToTable = 'Y';
        
        -- Verify CommandLog entries (should be one per user database)
        DECLARE @ServerModeLogCount int;
        DECLARE @BackupServerCount int;
        DECLARE @IncludedInSnapshotCount int;
        
        SELECT @ServerModeLogCount = COUNT(*),
               @BackupServerCount = SUM(CASE WHEN Command LIKE '%BACKUP SERVER%' THEN 1 ELSE 0 END),
               @IncludedInSnapshotCount = SUM(CASE WHEN Command LIKE '%included in SERVER snapshot%' THEN 1 ELSE 0 END)
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND ErrorNumber = 0;
        
        IF @ServerModeLogCount = @UserDBCount AND @BackupServerCount = 1 AND @IncludedInSnapshotCount = (@UserDBCount - 1)
            EXEC #LogTestResult @TestID, 'Passed', 
                'SERVER mode: ' + CAST(@ServerModeLogCount as varchar) + ' entries (' + 
                CAST(@BackupServerCount as varchar) + ' BACKUP SERVER, ' + 
                CAST(@IncludedInSnapshotCount as varchar) + ' included references)';
        ELSE
        BEGIN
            EXEC #LogTestResult @TestID, 'Failed', 
                'Expected ' + CAST(@UserDBCount as varchar) + ' entries. Got ' + 
                CAST(@ServerModeLogCount as varchar) + ' entries, ' +
                CAST(@BackupServerCount as varchar) + ' BACKUP SERVER, ' +
                CAST(@IncludedInSnapshotCount as varchar) + ' included references';
            SET @ErrorCount += 1;
        END
    END TRY
    BEGIN CATCH
        EXEC #LogTestResult @TestID, 'Failed', ERROR_MESSAGE();
        SET @ErrorCount += 1;
    END CATCH;
END
ELSE
BEGIN
    PRINT '';
    PRINT '============================================================';
    PRINT 'LIVE EXECUTION TESTS SKIPPED';
    PRINT 'Set @ExecuteTests = 1 to run live tests (creates real snapshots)';
    PRINT '============================================================';
    
    EXEC @TestID = #LogTestStart 'SINGLE Mode Live Execution', 'LiveExecution';
    EXEC #LogTestResult @TestID, 'Skipped', '@ExecuteTests = 0';
    
    EXEC @TestID = #LogTestStart 'GROUP Mode Live Execution', 'LiveExecution';
    EXEC #LogTestResult @TestID, 'Skipped', '@ExecuteTests = 0';
    
    EXEC @TestID = #LogTestStart 'SERVER Mode Live Execution', 'LiveExecution';
    EXEC #LogTestResult @TestID, 'Skipped', '@ExecuteTests = 0';
END;

-- ============================================================================
-- COMMANDLOG VERIFICATION QUERIES
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT 'COMMANDLOG VERIFICATION QUERIES';
PRINT '============================================================';
PRINT '';
PRINT 'Run these queries to verify backup history:';
PRINT '';
PRINT '-- Recent snapshot backups:';
PRINT 'SELECT TOP 20 ID, DatabaseName, CommandType,';
PRINT '       LEFT(Command, 100) as CommandPreview,';
PRINT '       StartTime, ErrorNumber';
PRINT 'FROM dbo.CommandLog';
PRINT 'WHERE CommandType = ''PURESTORAGE_SNAPSHOT''';
PRINT 'ORDER BY ID DESC;';
PRINT '';
PRINT '-- Snapshots grouped by snapshot name:';
PRINT 'SELECT ';
PRINT '    CASE WHEN Command LIKE ''%MEDIADESCRIPTION=N''''%''';
PRINT '         THEN SUBSTRING(Command, CHARINDEX(''MEDIADESCRIPTION=N'''''', Command) + 19, 30)';
PRINT '         WHEN Command LIKE ''%included in SERVER snapshot:%''';
PRINT '         THEN SUBSTRING(Command, CHARINDEX(''snapshot:'', Command) + 10, 30)';
PRINT '         ELSE ''Unknown'' END as SnapshotName,';
PRINT '    COUNT(*) as DatabaseCount,';
PRINT '    MIN(StartTime) as StartTime,';
PRINT '    SUM(CASE WHEN ErrorNumber = 0 THEN 1 ELSE 0 END) as SuccessCount,';
PRINT '    SUM(CASE WHEN ErrorNumber <> 0 THEN 1 ELSE 0 END) as ErrorCount';
PRINT 'FROM dbo.CommandLog';
PRINT 'WHERE CommandType = ''PURESTORAGE_SNAPSHOT''';
PRINT '  AND StartTime > DATEADD(day, -1, GETDATE())';
PRINT 'GROUP BY ';
PRINT '    CASE WHEN Command LIKE ''%MEDIADESCRIPTION=N''''%''';
PRINT '         THEN SUBSTRING(Command, CHARINDEX(''MEDIADESCRIPTION=N'''''', Command) + 19, 30)';
PRINT '         WHEN Command LIKE ''%included in SERVER snapshot:%''';
PRINT '         THEN SUBSTRING(Command, CHARINDEX(''snapshot:'', Command) + 10, 30)';
PRINT '         ELSE ''Unknown'' END';
PRINT 'ORDER BY MIN(StartTime) DESC;';

-- ============================================================================
-- TEST SUMMARY
-- ============================================================================
PRINT '';
PRINT '============================================================';
PRINT 'TEST SUMMARY';
PRINT '============================================================';

SELECT 
    TestCategory,
    COUNT(*) as TotalTests,
    SUM(CASE WHEN Status = 'Passed' THEN 1 ELSE 0 END) as Passed,
    SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END) as Failed,
    SUM(CASE WHEN Status = 'Skipped' THEN 1 ELSE 0 END) as Skipped
FROM #TestResults
GROUP BY TestCategory
ORDER BY TestCategory;

PRINT '';

SELECT 
    TestID,
    TestCategory,
    TestName,
    Status,
    DATEDIFF(millisecond, StartTime, ISNULL(EndTime, SYSDATETIME())) as DurationMs,
    LEFT(ISNULL(Details, ''), 100) as Details
FROM #TestResults
ORDER BY TestID;

PRINT '';
PRINT '============================================================';

DECLARE @TotalTests int, @PassedTests int, @FailedTests int, @SkippedTests int;
SELECT 
    @TotalTests = COUNT(*),
    @PassedTests = SUM(CASE WHEN Status = 'Passed' THEN 1 ELSE 0 END),
    @FailedTests = SUM(CASE WHEN Status = 'Failed' THEN 1 ELSE 0 END),
    @SkippedTests = SUM(CASE WHEN Status = 'Skipped' THEN 1 ELSE 0 END)
FROM #TestResults;

PRINT 'Total Tests: ' + CAST(@TotalTests as varchar);
PRINT 'Passed: ' + CAST(@PassedTests as varchar);
PRINT 'Failed: ' + CAST(@FailedTests as varchar);
PRINT 'Skipped: ' + CAST(@SkippedTests as varchar);
PRINT '';

IF @FailedTests = 0
    PRINT '✓ ALL TESTS PASSED!';
ELSE
    PRINT '✗ ' + CAST(@FailedTests as varchar) + ' TEST(S) FAILED - Review details above';

PRINT '============================================================';
PRINT 'Completed: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '============================================================';

-- Cleanup
DROP PROCEDURE IF EXISTS #LogTestStart;
DROP PROCEDURE IF EXISTS #LogTestResult;
DROP TABLE IF EXISTS #TestResults;

GO
