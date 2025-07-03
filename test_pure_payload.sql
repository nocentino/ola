-- Test Pure Storage payload construction to debug HTTP 400 error
-- This script tests the exact JSON payload that would be sent by DatabaseBackup.sql

DECLARE @ret INT, @response NVARCHAR(MAX), @AuthToken NVARCHAR(MAX), @MyHeaders NVARCHAR(MAX);
DECLARE @SnapshotName NVARCHAR(255), @ErrorMessage NVARCHAR(MAX);
DECLARE @InstanceName NVARCHAR(128) = REPLACE(@@SERVERNAME, '\', '_');
DECLARE @DateStamp NVARCHAR(20) = REPLACE(CONVERT(NVARCHAR, GETDATE(), 112) + '_' + REPLACE(CONVERT(NVARCHAR, GETDATE(), 108), ':', ''), ' ', '_');

BEGIN TRY
    -- Login to Pure Storage array using the same URL/token as in olasnapsho.sql
    EXEC @ret = sp_invoke_external_rest_endpoint
         @url = N'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44/login',
         @headers = N'{"api-token":"3b078aa4-94a8-68da-8e7b-04aec357f678"}',
         @response = @response OUTPUT;

    PRINT 'Login Return Code: ' + CAST(@ret AS NVARCHAR(10));
    PRINT 'Login Response: ' + @response;

    IF (@ret <> 0)
    BEGIN
        SET @ErrorMessage = 'Error logging in to Pure Storage array. Return code: ' + CAST(@ret AS NVARCHAR(10));
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END

    -- Extract auth token
    SET @AuthToken = JSON_VALUE(@response, '$.response.headers."x-auth-token"');
    IF (@AuthToken IS NULL OR @AuthToken = '')
    BEGIN
        RAISERROR('Failed to extract authentication token from response', 16, 1);
        RETURN;
    END
    
    SET @MyHeaders = N'{"x-auth-token":"' + @AuthToken + '", "Content-Type":"application/json"}';
    PRINT 'Authentication successful';

    -- Build payload exactly as DatabaseBackup.sql would construct it
    DECLARE @Payload NVARCHAR(MAX);
    SET @Payload = '{"source_names": "aen-sql-25-a-pg", "replicate_now": false, "tags": ['+
        '{"copyable": true, "key": "DatabaseName", "value": "TPCC-4T"},'+
        '{"copyable": true, "key": "SQLInstanceName", "value": "' + @InstanceName + '"},'+
        '{"copyable": true, "key": "BackupTimestamp", "value": "' + @DateStamp + '"},'+
        '{"copyable": true, "key": "BackupType", "value": "SNAPSHOT"},'+
        '{"copyable": true, "key": "BackupSoftware", "value": "Ola_Hallengren_PURESTORAGE_SNAPSHOT"}'+
        ']}';

    PRINT 'Payload: ' + @Payload;

    -- Test JSON validity
    DECLARE @TestJson NVARCHAR(MAX) = @Payload;
    IF (ISJSON(@TestJson) = 0)
    BEGIN
        RAISERROR('Generated payload is not valid JSON', 16, 1);
        RETURN;
    END
    ELSE
    BEGIN
        PRINT 'Payload is valid JSON';
    END

    -- Create snapshot
    PRINT 'Creating Pure Storage snapshot for Protection Group: aen-sql-25-a-pg';
    EXEC @ret = sp_invoke_external_rest_endpoint
         @url = N'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.44/protection-group-snapshots',
         @headers = @MyHeaders,
         @payload = @Payload,
         @response = @response OUTPUT;

    PRINT 'Snapshot Return Code: ' + CAST(@ret AS NVARCHAR(10));
    PRINT 'Snapshot Response: ' + @response;

    -- Process result
    IF (@ret = 0)
    BEGIN
        SET @SnapshotName = JSON_VALUE(@response, '$.result.items[0].name');
        IF (@SnapshotName IS NULL OR @SnapshotName = '')
        BEGIN
            PRINT 'WARNING: Failed to extract snapshot name from response';
            PRINT 'Response was: ' + ISNULL(@response, 'NULL');
        END
        ELSE
        BEGIN
            PRINT 'Snapshot created successfully. Name: ' + @SnapshotName;
        END
    END
    ELSE
    BEGIN
        SET @ErrorMessage = 'Error creating snapshot. Return code: ' + CAST(@ret AS NVARCHAR(10)) + ', Response: ' + ISNULL(@response, 'NULL');
        PRINT @ErrorMessage;
    END

END TRY
BEGIN CATCH
    SET @ErrorMessage = ERROR_MESSAGE();
    PRINT 'Error: ' + @ErrorMessage;
END CATCH
