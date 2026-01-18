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


SELECT TOP 10
    ID, DatabaseName, CommandType, Command, 
    StartTime, EndTime, ErrorNumber, ErrorMessage
FROM dbo.CommandLog 
WHERE DatabaseName = 'TPCC-4T'
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
WHERE DatabaseName IN ('TPCC-4T', 'TPCC500G')
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
SELECT TOP 20
    ID, DatabaseName, CommandType, Command, 
    StartTime, EndTime, ErrorNumber, ErrorMessage
FROM dbo.CommandLog
ORDER BY StartTime DESC;


-- Query latest snapshot via REST API
-- Step 1: Authenticate to get session token
DECLARE @PureStorageArrayURL nvarchar(max) = 'https://sn1-x90r2-f06-33.puretec.purestorage.com/api/2.46';
DECLARE @PureStorageAPIToken nvarchar(max) = '3b078aa4-94a8-68da-8e7b-04aec357f678';
DECLARE @PureStorageProtectionGroup nvarchar(max) = 'aen-sql-25-a-pg';

DECLARE @LoginURL nvarchar(max) = @PureStorageArrayURL + '/login';
DECLARE @LoginResponse nvarchar(max);
DECLARE @AuthToken nvarchar(max);

EXEC sp_invoke_external_rest_endpoint
    @url = @LoginURL,
    @method = 'POST',
    @headers = '{"api-token": "3b078aa4-94a8-68da-8e7b-04aec357f678"}',
    @response = @LoginResponse OUTPUT;

-- Extract the x-auth-token from response headers
SET @AuthToken = JSON_VALUE(@LoginResponse, '$.response.headers."x-auth-token"');

PRINT 'Auth Token: ' + ISNULL(@AuthToken, 'NULL - Authentication failed');

-- Step 2: Query snapshots using the session token
IF @AuthToken IS NOT NULL
BEGIN
    DECLARE @SnapshotURL nvarchar(max) = @PureStorageArrayURL + '/protection-group-snapshots';
    SET @SnapshotURL += '?source_names=' + @PureStorageProtectionGroup + '&sort=created-&limit=5';

    DECLARE @SnapshotResponse nvarchar(max);
    DECLARE @Headers nvarchar(max) = '{"x-auth-token": "' + @AuthToken + '"}';

    EXEC sp_invoke_external_rest_endpoint
        @url = @SnapshotURL,
        @method = 'GET',
        @headers = @Headers,
        @response = @SnapshotResponse OUTPUT;

    -- Display snapshot names and creation times
    SELECT 
        JSON_VALUE(value, '$.name') AS SnapshotName,
        JSON_VALUE(value, '$.created') AS Created,
        JSON_VALUE(value, '$.source.name') AS ProtectionGroup
    FROM OPENJSON(@SnapshotResponse, '$.result.items');

    -- Step 3: Query tags for these snapshots
    -- Build comma-separated list of snapshot names for the filter
    DECLARE @SnapshotNames nvarchar(max) = '';
    SELECT @SnapshotNames = @SnapshotNames + JSON_VALUE(value, '$.name') + ','
    FROM OPENJSON(@SnapshotResponse, '$.result.items');
    
    -- Remove trailing comma
    IF LEN(@SnapshotNames) > 0
        SET @SnapshotNames = LEFT(@SnapshotNames, LEN(@SnapshotNames) - 1);

    DECLARE @TagsURL nvarchar(max) = @PureStorageArrayURL + '/protection-group-snapshots/tags';
    SET @TagsURL += '?resource_names=' + @SnapshotNames;

    DECLARE @TagsResponse nvarchar(max);

    EXEC sp_invoke_external_rest_endpoint
        @url = @TagsURL,
        @method = 'GET',
        @headers = @Headers,
        @response = @TagsResponse OUTPUT;

    -- Display tags grouped by snapshot
    SELECT 
        JSON_VALUE(value, '$.resource.name') AS SnapshotName,
        JSON_VALUE(value, '$.key') AS TagKey,
        JSON_VALUE(value, '$.value') AS TagValue
    FROM OPENJSON(@TagsResponse, '$.result.items')
    ORDER BY JSON_VALUE(value, '$.resource.name'), JSON_VALUE(value, '$.key');
END