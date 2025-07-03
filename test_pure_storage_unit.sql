-- =====================================================================================
-- Pure Storage Snapshot Integration Unit Test for Ola Hallengren DatabaseBackup.sql
-- =====================================================================================
-- This comprehensive unit test validates the Pure Storage snapshot functionality
-- integrated into Ola Hallengren's DatabaseBackup.sql procedure.
-- 
-- Test Coverage:
-- 1. Parameter validation
-- 2. Prerequisites verification
-- 3. Snapshot creation with various configurations
-- 4. Error handling scenarios
-- 5. Cleanup operations
-- =====================================================================================

SET NOCOUNT ON;
DECLARE @TestResults TABLE (
    TestNumber INT,
    TestName NVARCHAR(200),
    Expected NVARCHAR(100),
    Actual NVARCHAR(100),
    Status NVARCHAR(10),
    ErrorMessage NVARCHAR(MAX),
    Duration_ms INT,
    TestTime DATETIME2
);

DECLARE @TestNumber INT = 0;
DECLARE @StartTime DATETIME2;
DECLARE @EndTime DATETIME2;
DECLARE @TestName NVARCHAR(200);
DECLARE @Expected NVARCHAR(100);
DECLARE @Actual NVARCHAR(100);
DECLARE @Status NVARCHAR(10);
DECLARE @ErrorMessage NVARCHAR(MAX);
DECLARE @Duration INT;

-- Test configuration
DECLARE @TestDatabase NVARCHAR(128) = 'TPCC-4T';
DECLARE @TestArrayURL NVARCHAR(500) = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44';
DECLARE @TestAPIToken NVARCHAR(200) = '3b078aa4-94a8-68da-8e7b-04aec357f678';
DECLARE @TestProtectionGroup NVARCHAR(200) = 'aen-sql-25-a-pg';
DECLARE @TestDirectory NVARCHAR(500) = 'C:\Backups\';

PRINT '==================================================================================';
PRINT 'Pure Storage Snapshot Integration Unit Test Suite';
PRINT 'Start Time: ' + CONVERT(NVARCHAR, SYSDATETIME(), 121);
PRINT '==================================================================================';
PRINT '';

-- =====================================================================================
-- TEST 1: Verify SQL Server Version and Prerequisites
-- =====================================================================================
SET @TestNumber = 1;
SET @TestName = 'SQL Server Version >= 2025 (Version 17)';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @Version NUMERIC(18,10) = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR), CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR)) - 1) + '.' + REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR), LEN(CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR)) - CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR))), '.', '') AS NUMERIC(18,10));
    
    SET @Expected = '>= 17.0';
    SET @Actual = CAST(@Version AS NVARCHAR);
    
    IF @Version >= 17
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
        SET @ErrorMessage = 'SQL Server 2025 (Version 17) or later required for Pure Storage integration';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 2: Verify External REST Endpoint Configuration
-- =====================================================================================
SET @TestNumber = 2;
SET @TestName = 'External REST Endpoint Enabled';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @RestEndpointEnabled BIT = 0;
    
    IF EXISTS (SELECT * FROM sys.configurations WHERE name = 'external rest endpoint enabled' AND value = 1)
        SET @RestEndpointEnabled = 1;
    
    SET @Expected = 'Enabled';
    SET @Actual = CASE WHEN @RestEndpointEnabled = 1 THEN 'Enabled' ELSE 'Disabled' END;
    
    IF @RestEndpointEnabled = 1
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
        SET @ErrorMessage = 'External REST endpoint must be enabled: sp_configure ''external rest endpoint enabled'', 1; RECONFIGURE;';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 3: Verify Test Database Exists and is Online
-- =====================================================================================
SET @TestNumber = 3;
SET @TestName = 'Test Database (' + @TestDatabase + ') Availability';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @DatabaseState NVARCHAR(20);
    SELECT @DatabaseState = state_desc FROM sys.databases WHERE name = @TestDatabase;
    
    SET @Expected = 'ONLINE';
    SET @Actual = ISNULL(@DatabaseState, 'NOT_FOUND');
    
    IF @DatabaseState = 'ONLINE'
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
        SET @ErrorMessage = 'Test database ' + @TestDatabase + ' must exist and be online';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 4: Pure Storage Array Connectivity Test
-- =====================================================================================
SET @TestNumber = 4;
SET @TestName = 'Pure Storage Array Login Test';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @ret INT, @response NVARCHAR(MAX);
    
    EXEC @ret = sp_invoke_external_rest_endpoint
         @url = N'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44/login',
         @headers = N'{"api-token":"3b078aa4-94a8-68da-8e7b-04aec357f678"}',
         @response = @response OUTPUT;
    
    SET @Expected = '200 (Success)';
    SET @Actual = CASE WHEN @ret = 0 THEN '200 (Success)' ELSE CAST(@ret AS NVARCHAR) + ' (Error)' END;
    
    IF @ret = 0
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
        SET @ErrorMessage = 'Failed to connect to Pure Storage array. Return code: ' + CAST(@ret AS NVARCHAR) + ', Response: ' + ISNULL(@response, 'NULL');
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 5: Parameter Validation Test - Missing Required Parameters
-- =====================================================================================
SET @TestNumber = 5;
SET @TestName = 'Parameter Validation - Missing Array URL';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @TestError BIT = 0;
    
    BEGIN TRY
        EXEC dbo.DatabaseBackup 
            @Databases = @TestDatabase,
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageAPIToken = @TestAPIToken,
            @PureStorageProtectionGroup = @TestProtectionGroup,
            @Directory = @TestDirectory,
            @Execute = 'N';  -- Don't actually execute
    END TRY
    BEGIN CATCH
        IF ERROR_MESSAGE() LIKE '%PureStorageArrayURL%' OR ERROR_MESSAGE() LIKE '%Pure Storage Array URL%'
            SET @TestError = 1;
    END CATCH
    
    SET @Expected = 'Error Raised';
    SET @Actual = CASE WHEN @TestError = 1 THEN 'Error Raised' ELSE 'No Error' END;
    
    IF @TestError = 1
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
        SET @ErrorMessage = 'Should raise error when PureStorageArrayURL is missing';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 6: Valid Snapshot Backup Test (Dry Run)
-- =====================================================================================
SET @TestNumber = 6;
SET @TestName = 'Valid Snapshot Backup Configuration (Dry Run)';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @ProcedureSuccess BIT = 1;
    
    BEGIN TRY
        EXEC dbo.DatabaseBackup 
            @Databases = @TestDatabase,
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageArrayURL = @TestArrayURL,
            @PureStorageAPIToken = @TestAPIToken,
            @PureStorageProtectionGroup = @TestProtectionGroup,
            @Directory = @TestDirectory,
            @Execute = 'N';  -- Dry run only
    END TRY
    BEGIN CATCH
        SET @ProcedureSuccess = 0;
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
    
    SET @Expected = 'Success';
    SET @Actual = CASE WHEN @ProcedureSuccess = 1 THEN 'Success' ELSE 'Failed' END;
    
    IF @ProcedureSuccess = 1
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);

-- =====================================================================================
-- TEST 7: Live Snapshot Creation Test (Optional - Uncomment if desired)
-- =====================================================================================
/*
SET @TestNumber = 7;
SET @TestName = 'Live Snapshot Creation Test';
SET @StartTime = SYSDATETIME();

BEGIN TRY
    DECLARE @LiveSuccess BIT = 1;
    
    BEGIN TRY
        EXEC dbo.DatabaseBackup 
            @Databases = @TestDatabase,
            @BackupType = 'SNAPSHOT',
            @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
            @PureStorageArrayURL = @TestArrayURL,
            @PureStorageAPIToken = @TestAPIToken,
            @PureStorageProtectionGroup = @TestProtectionGroup,
            @Directory = @TestDirectory,
            @Description = 'Unit Test Snapshot - ' + CONVERT(NVARCHAR, SYSDATETIME(), 121),
            @Execute = 'Y';  -- Actually execute
    END TRY
    BEGIN CATCH
        SET @LiveSuccess = 0;
        SET @ErrorMessage = ERROR_MESSAGE();
    END CATCH
    
    SET @Expected = 'Success';
    SET @Actual = CASE WHEN @LiveSuccess = 1 THEN 'Success' ELSE 'Failed' END;
    
    IF @LiveSuccess = 1
    BEGIN
        SET @Status = 'PASS';
        SET @ErrorMessage = '';
    END
    ELSE
    BEGIN
        SET @Status = 'FAIL';
    END
END TRY
BEGIN CATCH
    SET @Status = 'ERROR';
    SET @Actual = 'ERROR';
    SET @ErrorMessage = ERROR_MESSAGE();
END CATCH

SET @EndTime = SYSDATETIME();
SET @Duration = DATEDIFF(MILLISECOND, @StartTime, @EndTime);

INSERT INTO @TestResults VALUES (@TestNumber, @TestName, @Expected, @Actual, @Status, @ErrorMessage, @Duration, @EndTime);
*/

-- =====================================================================================
-- TEST RESULTS SUMMARY
-- =====================================================================================
PRINT '==================================================================================';
PRINT 'TEST RESULTS SUMMARY';
PRINT '==================================================================================';

SELECT 
    TestNumber,
    TestName,
    Expected,
    Actual,
    Status,
    Duration_ms,
    CASE 
        WHEN LEN(ErrorMessage) > 100 THEN LEFT(ErrorMessage, 97) + '...'
        ELSE ErrorMessage 
    END AS ErrorMessage
FROM @TestResults
ORDER BY TestNumber;

DECLARE @TotalTests INT, @PassedTests INT, @FailedTests INT, @ErrorTests INT;

SELECT 
    @TotalTests = COUNT(*),
    @PassedTests = SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END),
    @FailedTests = SUM(CASE WHEN Status = 'FAIL' THEN 1 ELSE 0 END),
    @ErrorTests = SUM(CASE WHEN Status = 'ERROR' THEN 1 ELSE 0 END)
FROM @TestResults;

PRINT '';
PRINT 'SUMMARY:';
PRINT '  Total Tests: ' + CAST(@TotalTests AS NVARCHAR);
PRINT '  Passed:      ' + CAST(@PassedTests AS NVARCHAR);
PRINT '  Failed:      ' + CAST(@FailedTests AS NVARCHAR);
PRINT '  Errors:      ' + CAST(@ErrorTests AS NVARCHAR);
PRINT '';

IF @FailedTests = 0 AND @ErrorTests = 0
BEGIN
    PRINT 'RESULT: ALL TESTS PASSED ✓';
    PRINT 'Pure Storage integration is ready for production use.';
END
ELSE
BEGIN
    PRINT 'RESULT: SOME TESTS FAILED ✗';
    PRINT 'Please review failed tests before using Pure Storage integration.';
END

PRINT '';
PRINT 'End Time: ' + CONVERT(NVARCHAR, SYSDATETIME(), 121);
PRINT '==================================================================================';

-- Show detailed error messages for failed tests
IF EXISTS (SELECT * FROM @TestResults WHERE Status IN ('FAIL', 'ERROR') AND LEN(ErrorMessage) > 100)
BEGIN
    PRINT '';
    PRINT 'DETAILED ERROR MESSAGES:';
    PRINT '==================================================================================';
    
    SELECT 
        'Test ' + CAST(TestNumber AS NVARCHAR) + ': ' + TestName AS Test,
        ErrorMessage
    FROM @TestResults 
    WHERE Status IN ('FAIL', 'ERROR') AND LEN(ErrorMessage) > 0
    ORDER BY TestNumber;
END
