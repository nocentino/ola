# Pure Storage FlashArray Integration for Ola Hallengren's SQL Server Maintenance Solution

This repository extends [Ola Hallengren's SQL Server Maintenance Solution](https://ola.hallengren.com/) with Pure Storage FlashArray snapshot backup capabilities using SQL Server 2025's `BACKUP SERVER` and `SUSPEND_FOR_SNAPSHOT_BACKUP` features.

## Overview

The integration enables hardware-based snapshot backups through Pure Storage FlashArray protection groups, providing:

- **Near-instant backups** regardless of database size
- **Application-consistent snapshots** using SQL Server's freeze/thaw mechanism
- **Three snapshot modes** for flexible backup strategies
- **Automatic tagging** for snapshot identification and recovery

## Requirements

- **SQL Server 2025** or later (required for `sp_invoke_external_rest_endpoint` and `BACKUP SERVER`)
- **Pure Storage FlashArray** with REST API v2.x
- **Protection Group** configured with volumes containing SQL Server data files
- **API Token** with permissions to create snapshots and manage tags

## Installation

1. Install the main solution:
   ```sql
   -- Run MaintenanceSolution.sql to create all required objects
   :r MaintenanceSolution.sql
   ```

2. Configure the Pure Storage connection in `olasnapshot.sql` and execute to set up the environment.

## New Parameters

The `DatabaseBackup` stored procedure includes these new parameters for Pure Storage integration:

| Parameter | Description |
|-----------|-------------|
| `@BackupType` | Set to `'SNAPSHOT'` for snapshot backups |
| `@BackupSoftware` | Set to `'PURESTORAGE_SNAPSHOT'` |
| `@PureStorageArrayURL` | FlashArray REST API URL (e.g., `'https://array.example.com/api/2.46'`) |
| `@PureStorageAPIToken` | API token for authentication |
| `@PureStorageProtectionGroup` | Protection group name containing database volumes |
| `@PureStorageReplicateNow` | `'Y'` to trigger immediate replication, `'N'` otherwise |
| `@SnapshotMode` | `'SINGLE'`, `'GROUP'`, or `'SERVER'` (see below) |

## Snapshot Modes

### SINGLE Mode
Creates one snapshot per database. Each database is frozen independently, a snapshot is taken, and the database is thawed.

```sql
EXECUTE dbo.DatabaseBackup
    @Databases = 'AdventureWorks2025',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://array.example.com/api/2.46',
    @PureStorageAPIToken = 'your-api-token',
    @PureStorageProtectionGroup = 'sql-protection-group',
    @PureStorageReplicateNow = 'N',
    @SnapshotMode = 'SINGLE',
    @LogToTable = 'Y',
    @Execute = 'Y';
```

**Best for:** Single database backups, testing, or when databases require individual snapshots.

### GROUP Mode
Creates a single snapshot containing all specified databases. All databases are frozen together, one snapshot is taken, and all databases are thawed.

```sql
EXECUTE dbo.DatabaseBackup
    @Databases = 'AdventureWorks2025, TPCC500G, TPCC-4T',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://array.example.com/api/2.46',
    @PureStorageAPIToken = 'your-api-token',
    @PureStorageProtectionGroup = 'sql-protection-group',
    @PureStorageReplicateNow = 'N',
    @SnapshotMode = 'GROUP',
    @LogToTable = 'Y',
    @Execute = 'Y';
```

**Best for:** Multi-database applications requiring point-in-time consistency across databases.

### SERVER Mode
Uses SQL Server 2025's `BACKUP SERVER` command to freeze all user databases with a single command, takes one snapshot, then thaws all databases.

```sql
EXECUTE dbo.DatabaseBackup
    @Databases = 'USER_DATABASES',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://array.example.com/api/2.46',
    @PureStorageAPIToken = 'your-api-token',
    @PureStorageProtectionGroup = 'sql-protection-group',
    @PureStorageReplicateNow = 'N',
    @SnapshotMode = 'SERVER',
    @LogToTable = 'Y',
    @Execute = 'Y';
```

**Best for:** Full server backups, disaster recovery, minimal freeze time across many databases.

## How It Works

### Authentication Flow
1. The procedure calls Pure Storage REST API `/login` endpoint with the API token
2. Receives a session token (`x-auth-token`) for subsequent API calls
3. Session token is used for snapshot creation and tag management

### Snapshot Creation Flow

#### SINGLE Mode:
```
For each database:
  1. BACKUP DATABASE ... WITH SUSPEND_FOR_SNAPSHOT_BACKUP
  2. POST /protection-group-snapshots (create snapshot)
  3. Apply tags to snapshot
  4. ALTER DATABASE ... SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF
```

#### GROUP Mode:
```
1. For each database: BACKUP DATABASE ... WITH SUSPEND_FOR_SNAPSHOT_BACKUP
2. POST /protection-group-snapshots (create single snapshot)
3. Apply tags to snapshot
4. For each database: ALTER DATABASE ... SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF
```

#### SERVER Mode:
```
1. BACKUP SERVER ... WITH SUSPEND_FOR_SNAPSHOT_BACKUP (freezes all user DBs)
2. POST /protection-group-snapshots (create single snapshot)
3. Apply tags to snapshot
4. ALTER SERVER SET SUSPEND_FOR_SNAPSHOT_BACKUP = OFF (thaws all DBs)
```

### Snapshot Tagging

Each snapshot is tagged with metadata for identification:

| Tag | Description |
|-----|-------------|
| `SnapshotMode` | SINGLE, GROUP, or SERVER |
| `DatabaseList` | Comma-separated list of database names |
| `ServerName` | SQL Server instance name |
| `BackupTime` | ISO 8601 timestamp of backup |

## CommandLog Integration

All operations are logged to the `dbo.CommandLog` table when `@LogToTable = 'Y'`:

```sql
-- View recent snapshot backups
SELECT 
    DatabaseName,
    CommandType,
    Command,
    StartTime,
    EndTime,
    ErrorNumber,
    ErrorMessage
FROM dbo.CommandLog
WHERE CommandType LIKE '%SNAPSHOT%'
ORDER BY StartTime DESC;
```

## Dry Run Mode

Test your configuration without executing commands:

```sql
EXECUTE dbo.DatabaseBackup
    @Databases = 'USER_DATABASES',
    @BackupType = 'SNAPSHOT',
    @BackupSoftware = 'PURESTORAGE_SNAPSHOT',
    @PureStorageArrayURL = 'https://array.example.com/api/2.46',
    @PureStorageAPIToken = 'your-api-token',
    @PureStorageProtectionGroup = 'sql-protection-group',
    @SnapshotMode = 'SERVER',
    @Execute = 'N';  -- Dry run - commands printed but not executed
```

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| "Pure Storage Snapshot backup requires SQL Server 2025" | Wrong SQL Server version | Upgrade to SQL Server 2025+ |
| "external REST endpoint feature not available" | Feature not enabled | Enable external REST endpoint in SQL Server config |
| "The value for @SnapshotMode is not supported" | Invalid mode | Use SINGLE, GROUP, or SERVER |
| API authentication failure | Invalid token | Verify API token permissions |

### Verifying Snapshots

Check snapshots on the FlashArray:

```sql
-- Query latest snapshot via REST API
DECLARE @url nvarchar(max) = 'https://array.example.com/api/2.46/protection-group-snapshots';
SET @url += '?source_names=sql-protection-group&sort=created-&limit=5';

EXEC sp_invoke_external_rest_endpoint
    @url = @url,
    @method = 'GET',
    @headers = '{"x-auth-token": "your-session-token"}';
```

## Files

| File | Description |
|------|-------------|
| `MaintenanceSolution.sql` | Complete solution with Pure Storage integration |
| `olasnapshot.sql` | Configuration and setup for snapshot backups |
| `DatabaseBackup_ORIG.sql` | Original Ola Hallengren DatabaseBackup procedure |

## Changes from Original

This fork adds the following to the original Ola Hallengren solution:

1. **New Parameters**: `@PureStorageArrayURL`, `@PureStorageAPIToken`, `@PureStorageProtectionGroup`, `@PureStorageReplicateNow`, `@SnapshotMode`
2. **New Backup Type**: `SNAPSHOT` for `@BackupType`
3. **New Backup Software**: `PURESTORAGE_SNAPSHOT` for `@BackupSoftware`
4. **Multi-database snapshot variables** for tracking freeze/thaw across databases
5. **Pure Storage REST API integration** for authentication, snapshot creation, and tagging
6. **SERVER mode support** using SQL Server 2025's `BACKUP SERVER` command
7. **QUOTENAME() fix** for hyphenated database names (e.g., `TPCC-4T`)

## License

This extension follows the same license as the original [Ola Hallengren SQL Server Maintenance Solution](https://ola.hallengren.com/).

## Credits

- **Ola Hallengren** - Original SQL Server Maintenance Solution
- **Pure Storage** - FlashArray REST API and snapshot technology
- **Microsoft** - SQL Server 2025 `BACKUP SERVER` and external REST endpoint features
