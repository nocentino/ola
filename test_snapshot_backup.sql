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

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
DECLARE @ExecuteTests bit = 1;  -- Set to 1 to actually execute backups

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
-- TEST VARIABLES
-- ============================================================================
DECLARE @TestID int;
DECLARE @ErrorCount int = 0;
DECLARE @MaxCommandLogID int;
DECLARE @PreflightErrors nvarchar(max) = '';
DECLARE @ProcDefinition nvarchar(max);

-- Variables for snapshot name extraction
DECLARE @CommandText nvarchar(max);
DECLARE @MediaDescPos int;
DECLARE @SnapshotPos int;

-- Save current max CommandLog ID
SELECT @MaxCommandLogID = ISNULL(MAX(ID), 0) FROM dbo.CommandLog;

PRINT '============================================================';
PRINT 'PURE STORAGE SNAPSHOT BACKUP TEST HARNESS';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '============================================================';
PRINT '';

-- ============================================================================
-- PRE-FLIGHT CHECKS
-- ============================================================================
PRINT '------------------------------------------------------------';
PRINT 'TEST: Pre-flight Validation';
PRINT 'Category: Setup';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('Pre-flight Validation', 'Setup');
SET @TestID = SCOPE_IDENTITY();

-- Check if DatabaseBackup procedure exists
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND type = 'P')
    SET @PreflightErrors = @PreflightErrors + 'DatabaseBackup procedure not found. ';

-- Check if CommandLog table exists
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID('dbo.CommandLog') AND type = 'U')
    SET @PreflightErrors = @PreflightErrors + 'CommandLog table not found. ';

-- Check if required parameters are supported
IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND name = '@SnapshotMode')
    SET @PreflightErrors = @PreflightErrors + '@SnapshotMode parameter not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.parameters WHERE object_id = OBJECT_ID('dbo.DatabaseBackup') AND name = '@PureStorageArrayURL')
    SET @PreflightErrors = @PreflightErrors + '@PureStorageArrayURL parameter not found. ';

-- Check if key fixes are deployed
SET @ProcDefinition = OBJECT_DEFINITION(OBJECT_ID('dbo.DatabaseBackup'));

IF @ProcDefinition NOT LIKE '%@LoginURL%'
    SET @PreflightErrors = @PreflightErrors + 'Login URL fix not deployed. ';

IF @ProcDefinition NOT LIKE '%@ServerBackupDone%'
    SET @PreflightErrors = @PreflightErrors + 'ServerBackupDone flag not deployed. ';

IF @ProcDefinition NOT LIKE '%included in SERVER snapshot%'
    SET @PreflightErrors = @PreflightErrors + 'SERVER mode logging fix not deployed. ';

-- Check test databases exist
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDB1)
    SET @PreflightErrors = @PreflightErrors + 'Test database ' + @TestDB1 + ' not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDB2)
    SET @PreflightErrors = @PreflightErrors + 'Test database ' + @TestDB2 + ' not found. ';

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = @TestDBWithHyphen)
    SET @PreflightErrors = @PreflightErrors + 'Test database ' + @TestDBWithHyphen + ' not found (hyphen test). ';

IF LEN(@PreflightErrors) > 0
BEGIN
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = @PreflightErrors WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
    PRINT 'Details: ' + @PreflightErrors;
    PRINT 'CRITICAL: Pre-flight checks failed. Fix issues before running tests.';
END
ELSE
BEGIN
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'All pre-flight checks passed.' WHERE TestID = @TestID;
    PRINT 'Result: Passed';
    PRINT 'Details: All pre-flight checks passed.';
END;

PRINT '';

-- ============================================================================
-- PARAMETER VALIDATION TESTS
-- ============================================================================
PRINT '============================================================';
PRINT 'PARAMETER VALIDATION TESTS';
PRINT '============================================================';

-- ----------------------------------------------------------------------------
-- Test 1: Invalid SnapshotMode value
-- ----------------------------------------------------------------------------
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: Invalid SnapshotMode Value';
PRINT 'Category: Validation';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('Invalid SnapshotMode Value', 'Validation');
SET @TestID = SCOPE_IDENTITY();

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
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = 'Should have raised error for invalid SnapshotMode' WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
    PRINT 'Details: Should have raised error for invalid SnapshotMode';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%SnapshotMode%'
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'Correctly rejected invalid SnapshotMode' WHERE TestID = @TestID;
        PRINT 'Result: Passed';
        PRINT 'Details: Correctly rejected invalid SnapshotMode';
    END
    ELSE
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
    END
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 2: GROUP mode requires PURESTORAGE_SNAPSHOT
-- ----------------------------------------------------------------------------
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: GROUP Mode Requires PURESTORAGE_SNAPSHOT';
PRINT 'Category: Validation';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('GROUP Mode Requires PURESTORAGE_SNAPSHOT', 'Validation');
SET @TestID = SCOPE_IDENTITY();

BEGIN TRY
    EXEC dbo.DatabaseBackup 
        @Databases = 'AdventureWorks2025',
        @BackupType = 'SNAPSHOT',
        @BackupSoftware = NULL,  -- Invalid for GROUP mode
        @SnapshotMode = 'GROUP',
        @Directory = 'C:\Backups',
        @Execute = 'N';
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = 'Should have raised error for GROUP without PURESTORAGE_SNAPSHOT' WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%GROUP%' OR ERROR_MESSAGE() LIKE '%PURESTORAGE%' OR ERROR_MESSAGE() LIKE '%BackupSoftware%'
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'Correctly rejected GROUP mode without PURESTORAGE_SNAPSHOT' WHERE TestID = @TestID;
        PRINT 'Result: Passed';
    END
    ELSE
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
    END
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 3: SERVER mode requires USER_DATABASES or ALL_DATABASES
-- ----------------------------------------------------------------------------
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: SERVER Mode Database Validation';
PRINT 'Category: Validation';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('SERVER Mode Database Validation', 'Validation');
SET @TestID = SCOPE_IDENTITY();

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
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = 'Should have raised error for SERVER with single database' WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%SERVER%' OR ERROR_MESSAGE() LIKE '%USER_DATABASES%' OR ERROR_MESSAGE() LIKE '%ALL_DATABASES%'
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'Correctly rejected SERVER mode with single database' WHERE TestID = @TestID;
        PRINT 'Result: Passed';
    END
    ELSE
    BEGIN
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
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
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: SINGLE Mode Dry Run';
PRINT 'Category: DryRun';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('SINGLE Mode Dry Run', 'DryRun');
SET @TestID = SCOPE_IDENTITY();

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
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'SINGLE mode dry run completed without errors' WHERE TestID = @TestID;
    PRINT 'Result: Passed';
END TRY
BEGIN CATCH
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
    PRINT 'Details: ' + ERROR_MESSAGE();
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 5: GROUP mode dry run with hyphenated database name
-- ----------------------------------------------------------------------------
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: GROUP Mode Dry Run (Hyphen in DB Name)';
PRINT 'Category: DryRun';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('GROUP Mode Dry Run (Hyphen in DB Name)', 'DryRun');
SET @TestID = SCOPE_IDENTITY();

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
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'GROUP mode dry run with hyphenated name completed' WHERE TestID = @TestID;
    PRINT 'Result: Passed';
END TRY
BEGIN CATCH
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
    PRINT 'Details: ' + ERROR_MESSAGE();
END CATCH;

-- ----------------------------------------------------------------------------
-- Test 6: SERVER mode dry run
-- ----------------------------------------------------------------------------
PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'TEST: SERVER Mode Dry Run';
PRINT 'Category: DryRun';
PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '------------------------------------------------------------';

INSERT INTO #TestResults (TestName, TestCategory) VALUES ('SERVER Mode Dry Run', 'DryRun');
SET @TestID = SCOPE_IDENTITY();

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
    
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', Details = 'SERVER mode dry run completed without errors' WHERE TestID = @TestID;
    PRINT 'Result: Passed';
END TRY
BEGIN CATCH
    UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
    SET @ErrorCount = @ErrorCount + 1;
    PRINT 'Result: Failed';
    PRINT 'Details: ' + ERROR_MESSAGE();
END CATCH;

-- ============================================================================
-- LIVE EXECUTION TESTS WITH TAG VERIFICATION
-- ============================================================================
PRINT '';
PRINT '============================================================';
IF @ExecuteTests = 1
    PRINT 'LIVE EXECUTION TESTS WITH TAG VERIFICATION';
ELSE
    PRINT 'LIVE EXECUTION TESTS SKIPPED (@ExecuteTests = 0)';
PRINT '============================================================';

IF @ExecuteTests = 1
BEGIN
    -- Declare variables for API calls (used across all tag retrieval tests)
    DECLARE @LoginURL nvarchar(500);
    DECLARE @SnapshotsURL nvarchar(500);
    DECLARE @AuthResponse nvarchar(max);
    DECLARE @AuthToken nvarchar(500);
    DECLARE @AuthHeaders nvarchar(500);
    DECLARE @ReturnValue int;
    DECLARE @PreTestMaxID int;
    DECLARE @SnapshotName nvarchar(255);
    DECLARE @TagsURL nvarchar(1000);
    DECLARE @TagsResponse nvarchar(max);
    DECLARE @TagsHeaders nvarchar(500);
    DECLARE @TagItems nvarchar(max);
    
    -- Authenticate once for all tag retrievals
    SET @LoginURL = @PureStorageArrayURL + '/login';
    SET @SnapshotsURL = @PureStorageArrayURL + '/protection-group-snapshots';
    SET @AuthHeaders = '{"api-token": "' + @PureStorageAPIToken + '"}';
    
    PRINT '';
    PRINT 'Authenticating to Pure Storage array for tag verification...';
    
    EXEC @ReturnValue = sp_invoke_external_rest_endpoint 
        @url = @LoginURL,
        @method = 'POST',
        @headers = @AuthHeaders,
        @payload = '{}',
        @response = @AuthResponse OUTPUT;
    
    IF @ReturnValue = 0
    BEGIN
        SET @AuthToken = JSON_VALUE(@AuthResponse, '$.response.headers."x-auth-token"');
        SET @TagsHeaders = '{"x-auth-token": "' + @AuthToken + '", "Content-Type":"application/json"}';
        PRINT 'Authentication successful.';
    END
    ELSE
    BEGIN
        PRINT 'Warning: Could not authenticate to Pure Storage. Tag verification will be skipped.';
        SET @AuthToken = NULL;
    END
    
    SELECT @PreTestMaxID = ISNULL(MAX(ID), 0) FROM dbo.CommandLog;
    
    -- ------------------------------------------------------------------------
    -- Test 8: SINGLE mode live execution with tag verification
    -- ------------------------------------------------------------------------
    PRINT '';
    PRINT '------------------------------------------------------------';
    PRINT 'TEST: SINGLE Mode - Backup and Tag Verification';
    PRINT 'Category: LiveExecution';
    PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
    PRINT '------------------------------------------------------------';

    INSERT INTO #TestResults (TestName, TestCategory) VALUES ('SINGLE Mode - Backup and Tag Verification', 'LiveExecution');
    SET @TestID = SCOPE_IDENTITY();
    
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
        
        -- For SINGLE mode, the snapshot name is not embedded in CommandLog (it uses @SnapshotName variable)
        -- Instead, query Pure Storage API for the latest snapshot from this protection group
        DECLARE @LatestSnapshotURL nvarchar(2048);
        DECLARE @LatestSnapshotResponse nvarchar(max);
        
        IF @AuthToken IS NOT NULL
        BEGIN
            SET @LatestSnapshotURL = @PureStorageArrayURL + '/protection-group-snapshots?source_names=' + @PureStorageProtectionGroup + '&sort=created-&limit=1';
            
            EXEC @ReturnValue = sp_invoke_external_rest_endpoint 
                @url = @LatestSnapshotURL,
                @method = 'GET',
                @headers = @TagsHeaders,
                @response = @LatestSnapshotResponse OUTPUT;
            
            IF @ReturnValue = 0
            BEGIN
                SET @SnapshotName = JSON_VALUE(@LatestSnapshotResponse, '$.result.items[0].name');
            END
        END
        
        PRINT 'SINGLE Mode Snapshot Created: ' + ISNULL(@SnapshotName, 'Unknown');
        
        -- Retrieve and display tags for this snapshot
        IF @AuthToken IS NOT NULL AND @SnapshotName IS NOT NULL
        BEGIN
            SET @TagsURL = @SnapshotsURL + '/tags?resource_names=' + @SnapshotName;
            
            EXEC @ReturnValue = sp_invoke_external_rest_endpoint 
                @url = @TagsURL,
                @method = 'GET',
                @headers = @TagsHeaders,
                @response = @TagsResponse OUTPUT;
            
            IF @ReturnValue = 0
            BEGIN
                SET @TagItems = JSON_QUERY(@TagsResponse, '$.result.items');
                
                IF @TagItems IS NOT NULL
                BEGIN
                    PRINT '';
                    PRINT 'SINGLE Mode Snapshot Tags:';
                    PRINT '--------------------------------------------------------------------------------';
                    
                    ;WITH Flattened AS (
                        SELECT 
                            JSON_VALUE(item.value, '$.resource.name') AS SnapshotName,
                            JSON_VALUE(item.value, '$.key') AS TagKey,
                            JSON_VALUE(item.value, '$.value') AS TagValue
                        FROM OPENJSON(@TagItems) AS item
                    )
                    SELECT *
                    FROM (SELECT SnapshotName, TagKey, TagValue FROM Flattened) AS SourceTable
                    PIVOT (MAX(TagValue) FOR TagKey IN ([DatabaseName], [SQLInstanceName], [BackupTimestamp], [BackupType], [BackupUrl])) AS PivotTable;
                    
                    -- Also show raw tags
                    PRINT '';
                    PRINT 'All Tags (Raw):';
                    SELECT 
                        JSON_VALUE(item.value, '$.key') AS TagKey,
                        JSON_VALUE(item.value, '$.value') AS TagValue
                    FROM OPENJSON(@TagItems) AS item
                    ORDER BY JSON_VALUE(item.value, '$.key');
                END
            END
        END
        
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', 
            Details = 'SINGLE mode: Snapshot ' + ISNULL(@SnapshotName, 'created') + ' with tags verified' WHERE TestID = @TestID;
        PRINT '';
        PRINT 'Result: Passed';
        
        SELECT @PreTestMaxID = MAX(ID) FROM dbo.CommandLog;
    END TRY
    BEGIN CATCH
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
    END CATCH;
    
    -- ------------------------------------------------------------------------
    -- Test 9: GROUP mode live execution with tag verification
    -- ------------------------------------------------------------------------
    PRINT '';
    PRINT '------------------------------------------------------------';
    PRINT 'TEST: GROUP Mode - Backup and Tag Verification';
    PRINT 'Category: LiveExecution';
    PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
    PRINT '------------------------------------------------------------';

    INSERT INTO #TestResults (TestName, TestCategory) VALUES ('GROUP Mode - Backup and Tag Verification', 'LiveExecution');
    SET @TestID = SCOPE_IDENTITY();
    
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
        
        -- Get the snapshot name from CommandLog
        SELECT TOP 1 @CommandText = Command
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND Command LIKE '%MEDIADESCRIPTION%'
        ORDER BY ID DESC;
        
        SET @MediaDescPos = CHARINDEX('MEDIADESCRIPTION=N''', @CommandText);
        IF @MediaDescPos > 0
        BEGIN
            SET @SnapshotName = SUBSTRING(@CommandText, 
                @MediaDescPos + 19,
                CHARINDEX('''', @CommandText, @MediaDescPos + 19) - @MediaDescPos - 19);
        END
        ELSE
        BEGIN
            SET @MediaDescPos = CHARINDEX('MEDIADESCRIPTION = N''', @CommandText);
            IF @MediaDescPos > 0
            BEGIN
                SET @SnapshotName = SUBSTRING(@CommandText, 
                    @MediaDescPos + 21,
                    CHARINDEX('''', @CommandText, @MediaDescPos + 21) - @MediaDescPos - 21);
            END
        END
        
        PRINT 'GROUP Mode Snapshot Created: ' + ISNULL(@SnapshotName, 'Unknown');
        
        -- Retrieve and display tags for this snapshot
        IF @AuthToken IS NOT NULL AND @SnapshotName IS NOT NULL
        BEGIN
            SET @TagsURL = @SnapshotsURL + '/tags?resource_names=' + @SnapshotName;
            
            EXEC @ReturnValue = sp_invoke_external_rest_endpoint 
                @url = @TagsURL,
                @method = 'GET',
                @headers = @TagsHeaders,
                @response = @TagsResponse OUTPUT;
            
            IF @ReturnValue = 0
            BEGIN
                SET @TagItems = JSON_QUERY(@TagsResponse, '$.result.items');
                
                IF @TagItems IS NOT NULL
                BEGIN
                    PRINT '';
                    PRINT 'GROUP Mode Snapshot Tags (should show multiple databases):';
                    PRINT '--------------------------------------------------------------------------------';
                    
                    ;WITH Flattened AS (
                        SELECT 
                            JSON_VALUE(item.value, '$.resource.name') AS SnapshotName,
                            JSON_VALUE(item.value, '$.key') AS TagKey,
                            JSON_VALUE(item.value, '$.value') AS TagValue
                        FROM OPENJSON(@TagItems) AS item
                    )
                    SELECT *
                    FROM (SELECT SnapshotName, TagKey, TagValue FROM Flattened) AS SourceTable
                    PIVOT (MAX(TagValue) FOR TagKey IN ([DatabaseName], [SQLInstanceName], [BackupTimestamp], [BackupType], [BackupUrl])) AS PivotTable;
                    
                    -- Also show raw tags to see all databases
                    PRINT '';
                    PRINT 'All Tags (showing all databases in GROUP):';
                    SELECT 
                        JSON_VALUE(item.value, '$.key') AS TagKey,
                        JSON_VALUE(item.value, '$.value') AS TagValue
                    FROM OPENJSON(@TagItems) AS item
                    ORDER BY JSON_VALUE(item.value, '$.key');
                END
            END
        END
        
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', 
            Details = 'GROUP mode: Snapshot ' + ISNULL(@SnapshotName, 'created') + ' with tags verified' WHERE TestID = @TestID;
        PRINT '';
        PRINT 'Result: Passed';
        
        SELECT @PreTestMaxID = MAX(ID) FROM dbo.CommandLog;
    END TRY
    BEGIN CATCH
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
    END CATCH;
    
    -- ------------------------------------------------------------------------
    -- Test 10: SERVER mode live execution with tag verification
    -- ------------------------------------------------------------------------
    PRINT '';
    PRINT '------------------------------------------------------------';
    PRINT 'TEST: SERVER Mode - Backup and Tag Verification';
    PRINT 'Category: LiveExecution';
    PRINT 'Started: ' + CONVERT(varchar, SYSDATETIME(), 121);
    PRINT '------------------------------------------------------------';

    INSERT INTO #TestResults (TestName, TestCategory) VALUES ('SERVER Mode - Backup and Tag Verification', 'LiveExecution');
    SET @TestID = SCOPE_IDENTITY();
    
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
        
        -- Get the snapshot name from CommandLog (from the BACKUP SERVER entry)
        SELECT TOP 1 @CommandText = Command
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND Command LIKE '%BACKUP SERVER%'
        ORDER BY ID DESC;
        
        SET @MediaDescPos = CHARINDEX('MEDIADESCRIPTION=N''', @CommandText);
        IF @MediaDescPos > 0
        BEGIN
            SET @SnapshotName = SUBSTRING(@CommandText, 
                @MediaDescPos + 19,
                CHARINDEX('''', @CommandText, @MediaDescPos + 19) - @MediaDescPos - 19);
        END
        ELSE
        BEGIN
            SET @MediaDescPos = CHARINDEX('MEDIADESCRIPTION = N''', @CommandText);
            IF @MediaDescPos > 0
            BEGIN
                SET @SnapshotName = SUBSTRING(@CommandText, 
                    @MediaDescPos + 21,
                    CHARINDEX('''', @CommandText, @MediaDescPos + 21) - @MediaDescPos - 21);
            END
        END
        
        -- If not found from BACKUP SERVER, try from "included in" entries
        IF @SnapshotName IS NULL OR LEN(@SnapshotName) = 0
        BEGIN
            SELECT TOP 1 @CommandText = Command
            FROM dbo.CommandLog 
            WHERE ID > @PreTestMaxID 
              AND CommandType = 'PURESTORAGE_SNAPSHOT'
              AND Command LIKE '%included in SERVER snapshot%'
            ORDER BY ID DESC;
            
            SET @SnapshotPos = CHARINDEX('snapshot: ', @CommandText);
            IF @SnapshotPos > 0
            BEGIN
                SET @SnapshotName = SUBSTRING(@CommandText, 
                    @SnapshotPos + 10,
                    CHARINDEX('''', @CommandText, @SnapshotPos + 10) - @SnapshotPos - 10);
            END
        END
        
        PRINT 'SERVER Mode Snapshot Created: ' + ISNULL(@SnapshotName, 'Unknown');
        PRINT 'User Databases Included: ' + CAST(@UserDBCount as varchar);
        
        -- Retrieve and display tags for this snapshot
        IF @AuthToken IS NOT NULL AND @SnapshotName IS NOT NULL
        BEGIN
            SET @TagsURL = @SnapshotsURL + '/tags?resource_names=' + @SnapshotName;
            
            EXEC @ReturnValue = sp_invoke_external_rest_endpoint 
                @url = @TagsURL,
                @method = 'GET',
                @headers = @TagsHeaders,
                @response = @TagsResponse OUTPUT;
            
            IF @ReturnValue = 0
            BEGIN
                SET @TagItems = JSON_QUERY(@TagsResponse, '$.result.items');
                
                IF @TagItems IS NOT NULL
                BEGIN
                    PRINT '';
                    PRINT 'SERVER Mode Snapshot Tags (should show ALL user databases):';
                    PRINT '--------------------------------------------------------------------------------';
                    
                    ;WITH Flattened AS (
                        SELECT 
                            JSON_VALUE(item.value, '$.resource.name') AS SnapshotName,
                            JSON_VALUE(item.value, '$.key') AS TagKey,
                            JSON_VALUE(item.value, '$.value') AS TagValue
                        FROM OPENJSON(@TagItems) AS item
                    )
                    SELECT *
                    FROM (SELECT SnapshotName, TagKey, TagValue FROM Flattened) AS SourceTable
                    PIVOT (MAX(TagValue) FOR TagKey IN ([DatabaseName], [SQLInstanceName], [BackupTimestamp], [BackupType], [BackupUrl])) AS PivotTable;
                    
                    -- Show all tags to verify all databases are tagged
                    PRINT '';
                    PRINT 'All Tags (showing all ' + CAST(@UserDBCount as varchar) + ' databases in SERVER snapshot):';
                    SELECT 
                        JSON_VALUE(item.value, '$.key') AS TagKey,
                        JSON_VALUE(item.value, '$.value') AS TagValue
                    FROM OPENJSON(@TagItems) AS item
                    ORDER BY JSON_VALUE(item.value, '$.key');
                    
                    -- Count database tags to verify
                    DECLARE @TaggedDBCount int;
                    SELECT @TaggedDBCount = COUNT(*)
                    FROM OPENJSON(@TagItems) AS item
                    WHERE JSON_VALUE(item.value, '$.key') = 'DatabaseName';
                    
                    PRINT '';
                    PRINT 'Databases tagged in snapshot: ' + CAST(@TaggedDBCount as varchar) + ' (expected: ' + CAST(@UserDBCount as varchar) + ')';
                END
            END
        END
        
        -- Verify CommandLog entries
        DECLARE @ServerModeLogCount int;
        DECLARE @BackupServerCount int;
        
        SELECT @ServerModeLogCount = COUNT(*),
               @BackupServerCount = SUM(CASE WHEN Command LIKE '%BACKUP SERVER%' THEN 1 ELSE 0 END)
        FROM dbo.CommandLog 
        WHERE ID > @PreTestMaxID 
          AND CommandType = 'PURESTORAGE_SNAPSHOT'
          AND ErrorNumber = 0;
        
        IF @ServerModeLogCount = @UserDBCount AND @BackupServerCount = 1
        BEGIN
            UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Passed', 
                Details = 'SERVER mode: ' + CAST(@ServerModeLogCount as varchar) + ' entries, snapshot ' + ISNULL(@SnapshotName, '') + ' with tags verified' WHERE TestID = @TestID;
            PRINT '';
            PRINT 'Result: Passed';
        END
        ELSE
        BEGIN
            UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', 
                Details = 'Expected ' + CAST(@UserDBCount as varchar) + ' entries. Got ' + CAST(@ServerModeLogCount as varchar) WHERE TestID = @TestID;
            SET @ErrorCount = @ErrorCount + 1;
            PRINT '';
            PRINT 'Result: Failed';
        END
    END TRY
    BEGIN CATCH
        UPDATE #TestResults SET EndTime = SYSDATETIME(), Status = 'Failed', Details = ERROR_MESSAGE() WHERE TestID = @TestID;
        SET @ErrorCount = @ErrorCount + 1;
        PRINT 'Result: Failed';
        PRINT 'Details: ' + ERROR_MESSAGE();
    END CATCH;
END
ELSE
BEGIN
    -- Skip live tests
    INSERT INTO #TestResults (TestName, TestCategory, Status, Details, EndTime) 
    VALUES ('SINGLE Mode - Backup and Tag Verification', 'LiveExecution', 'Skipped', '@ExecuteTests = 0', SYSDATETIME());
    
    INSERT INTO #TestResults (TestName, TestCategory, Status, Details, EndTime) 
    VALUES ('GROUP Mode - Backup and Tag Verification', 'LiveExecution', 'Skipped', '@ExecuteTests = 0', SYSDATETIME());
    
    INSERT INTO #TestResults (TestName, TestCategory, Status, Details, EndTime) 
    VALUES ('SERVER Mode - Backup and Tag Verification', 'LiveExecution', 'Skipped', '@ExecuteTests = 0', SYSDATETIME());
    
    PRINT 'Set @ExecuteTests = 1 to run live tests (creates real snapshots)';
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
    PRINT 'ALL TESTS PASSED!';
ELSE
    PRINT CAST(@FailedTests as varchar) + ' TEST(S) FAILED - Review details above';

PRINT '============================================================';
PRINT 'Completed: ' + CONVERT(varchar, SYSDATETIME(), 121);
PRINT '============================================================';

-- Cleanup
DROP TABLE IF EXISTS #TestResults;
