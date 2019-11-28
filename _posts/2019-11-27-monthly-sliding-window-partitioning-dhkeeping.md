---
layout: post
title: Design decisions and problems faced with during database housekeeping operations
---

Due to various reasons, such as [DSVGO/GDPR](https://en.wikipedia.org/wiki/General_Data_Protection_Regulation) you may want to clean up older data. This generally is also referred as Data Housekeeping, for whatever busines reasons. In this blog, we will analyze one such implementation, where we deprecate older than 12 months data.

## Database Housekeeping Design Decisions

- In order to accomplish housekeeping, we need to design a system responsible for running related task in a cronjob. To be able to perform deletion of old records, we should [partition the related table](https://www.cathrinewilhelmsen.net/2015/04/12/table-partitioning-in-sql-server/) first.

## Monthly Sliding Window Partitioning

- By dividing table into partitions rather than having a single table will ease identifying records that need to be deleted. Also, the classical delete command on the partitioned table will fill up the database transaction log quickly and it may take a very long time to complete. So, rather than directly deleting rows from the table, we can use partition switching which allows moving a partition between source and target tables very quickly. Since this operation is metadata-only, no data movement will happen during switching. So, it is very fast. To partition a table, first we have to create a partition function and schema. And then update our table definition according to defined partition schema. After this setup, housekeeping is performed with a cronjob that runs at first day of each month. At each run, oldest partition according to date is deleted and new partition is added. This is called [monthly sliding window partitioning](https://www.mssqltips.com/sqlservertip/5296/implementation-of-sliding-window-partitioning-in-sql-server-to-purge-data/).

1. Partition Schema
```
	CREATE PARTITION SCHEME [MyPSMonth] 
	AS PARTITION [MyPFMonth]
	ALL TO ( [PRIMARY] )
	GO
```

2. Partition Function

- This function identifies the boundary values for partitions. Since our purpose is deleting records older than 1 year, we have partitioned the table by month. While calculating boundary values, year and month fields are multiplied with related constants in order to place each inserted or existing records to its correct partition. Also, boundary values are described as range left so that each boundary value is the minimum value on its partition range. Basically, there are 14 boundary values that yields a total of 15 partitions. The extra partition on the end is just for precaution if partitioning on scheduled time does not work because of some transient errors. By doing so prevents latest partition overly occupied. 

```
	CREATE PARTITION FUNCTION [MyPFMonth](int) 
	AS RANGE LEFT FOR VALUES 
	(
		YEAR(DATEADD(MONTH, -12, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH, -12, GETUTCDATE())),
		YEAR(DATEADD(MONTH, -11, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH, -11, GETUTCDATE())),
		YEAR(DATEADD(MONTH, -10, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH, -10, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -9, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -9, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -8, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -8, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -7, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -7, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -6, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -6, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -5, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -5, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -4, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -4, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -3, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -3, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -2, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -2, GETUTCDATE())),
		YEAR(DATEADD(MONTH,  -1, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,  -1, GETUTCDATE())),
		YEAR(DATEADD(MONTH,   0, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,   0, GETUTCDATE())),
		YEAR(DATEADD(MONTH,   1, GETUTCDATE())) * 100 + MONTH(DATEADD(MONTH,   1, GETUTCDATE()))
	)
	GO
```

3. Table Definitions

- In order to apply partitioning on the table, we have to choose partition key and create table on partition schema. For better understanding the concept, we can take the below table definition into account. At first, we can choose partition key as `createdTime` column. This is ideal for start. However, we should choose it as `endTime` column. You can read [related post](2019-11-28-unique-const-dml-trigger-partitioned-table.md) for additional information about unique constraints in a partitioned table.
- Notice that, we have another table and index with exactly the same structure as the original ones except their names. The reason is that we are going to use partition switching. In order to perform switching, the following conditions must be satisfied:

	* Source and target tables must have identical columns and indexes
	* Both the source and target table must use the same column as the partition column
	* Both the source and target tables must be in the same filegroup
	* The target table must be empty

```
	CREATE TABLE [MySchema].[MyTableName]
	(
		[id] BIGINT NOT NULL IDENTITY(1,1),
		[name] NVARCHAR(20) NOT NULL,
		[startTime] DATETIME2 NOT NULL,
		[endTime] DATETIME2 NOT NULL,
		[createdTime] DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
		[partitionKey] AS (DATEPART(YEAR, [endTime]) * 100
							+ DATEPART(MONTH, [endTime])) PERSISTED NOT NULL
	) ON MyPSMonth ([partitionKey]);
	GO

	CREATE UNIQUE NONCLUSTERED INDEX [MyUniqueIndex]
		ON [MySchema].[MyTableName]([partitionKey] ASC, [name] ASC, [startTime] ASC)
	GO

	CREATE TABLE [MySchema].[MyTableNameDelete]
	(
		[id] BIGINT NOT NULL IDENTITY(1,1),
		[name] NVARCHAR(20) NOT NULL,
		[startTime] DATETIME2 NOT NULL,
		[endTime] DATETIME2 NOT NULL,
		[createdTime] DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
		[partitionKey] AS (DATEPART(YEAR, [endTime]) * 100
							+ DATEPART(MONTH, [endTime])) PERSISTED NOT NULL
	) ON MyPSMonth ([partitionKey]);
	GO

	CREATE UNIQUE NONCLUSTERED INDEX [MyUniqueIndexDelete]
		ON [MySchema].[MyTableNameDelete]([partitionKey] ASC, [name] ASC, [startTime] ASC)
	GO
```

4. Housekeeping Stored Procedure

- After defining table, partition schema and function it is time to perform the actual sliding window operation. To do that, we have to create a stored procedure that will be called by our cronjob. The skeleton for the procedure would be like the following:

```
	-- Go back 1 year
	SET @exDate = DATEADD(MONTH, -12, SYSUTCDATETIME()) 
	-- Calculate boundary value
	SET @exDateInt = YEAR(@exDate) * 100 + MONTH(@exDate);

	-- Determine new partition boundary values and add them to temporary table
	SET @countMonth = 0
	WHILE @countMonth < ( 2 )
	BEGIN 
		INSERT INTO #neededMonth 
		SELECT YEAR(DATEADD(MONTH,   @countMonth, @dateActual)) * 100 + MONTH(DATEADD(MONTH,   @countMonth, @dateActual))
		SET @countMonth = @countMonth + 1
	END

	SET @countMonth = -1;
	WHILE @countMonth >= ( -12 )
	BEGIN 
		INSERT INTO #neededMonth
		SELECT YEAR(DATEADD(MONTH,   @countMonth, @dateActual)) * 100 + MONTH(DATEADD(MONTH,   @countMonth, @dateActual))

		SET @countMonth = @countMonth - 1
	END

	-- Delete boundary values that are already existing
	DELETE FROM #neededMonth
	WHERE [Month] IN (
		SELECT [value] FROM [sys].[partition_functions] AS [PF]
		INNER JOIN [sys].[partition_range_values] AS [PRV]
		ON [PRV].[function_id] = [PF].[function_id]
		WHERE [PF].[name] = 'MyPFMonth'
	)

	-- Add new partitions with splitting partition range
	WHILE @NewBoundary exists in #neededMonth
	BEGIN

		-- Use same file group for upcoming partition
		ALTER PARTITION
			SCHEME MyPSMonth
		NEXT USED
			[PRIMARY];

		-- Create new partition
		ALTER PARTITION FUNCTION MyPFMonth()
			SPLIT RANGE (@NewBoundary);
	END

	-- Determine boundary ids that will be switched and add them to temporary table

	INSERT INTO #unnecessaryMonths
	SELECT DISTINCT [boundary_id], CAST([value] AS INT)
	FROM [sys].[partition_range_values] AS [PRV]
	INNER JOIN [sys].[partition_functions] AS [PF]
	ON [PRV].[function_id] = [PF].[function_id]
	WHERE [PF].[name] = 'MyPFMOnth' AND [PRV].[value] < @exDateInt
	ORDER BY [boundary_id] DESC;

	-- Clean up unnecessary partitions with switching
	WHILE @boundaryId exists in #unnecessaryMonths
	BEGIN

		-- Make sure target table is empty. Since it is a requirement for switching operation
		TRUNCATE TABLE [MySchema].[MyTableNameDelete]

		-- Perform switching
		ALTER TABLE [MySchema].[MyTableName]
				SWITCH PARTITION @boundaryId
				TO [MySchema].[MyTableNameDelete]
				PARTITION @boundaryId

		-- Actual clean operation is happening here
		TRUNCATE TABLE [MySchema].[MyTableNameDelete]
	END
```

* You may ask why not directly truncating partitions rather than switching them to `MyTableNameDelete` table. As mentioned in the beginning of `Monthly Sliding Window Partitioning` section, it is quicker and has better performance compared to classical delete.

## Designing Housekeeping Application

- We have total of 6 housekeeping tasks that need to be run in selected regular intervals. These includes index housekeeping for all the databases, data housekeeping for selected tables of specified databases, blob storage housekeeping for Azure storage account. Rather than creating separate application for all these tasks individually, we have decided to create a single console application to easily maintain housekeeping. Also, each task should be a cron job and scheduled at a different time. To do that, somehow we had to parameterize our application so that it can be run for all the tasks without a hassle. The housekeeping stored procedures don't really need `T-SQL arguments`, and we can simply extend the CronJob to handle any `SPROC` by just supplying arguments from the deployment manifests. For example, the following deployment manifest describes a CronJob object. By supplying application runtime parameters through `args`, we simply get related secrets from template file and then directly call related stored procedure defined in the corresponding database. By following this approach, we could add new cronjob deployments without a hassle.

```
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: "CronJob1"
spec:
  schedule: "0 2 1 * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  jobTemplate:
    metadata:
      labels:
        cronjob: "CronJob1"
    spec:
      template:
        metadata:
          labels:
            app: "Sample"
        spec:
          restartPolicy: Never
          securityContext:
            runAsUser: 10000
            runAsGroup: 30000
            runAsNonRoot: true
          containers:
          - name: test
            image: test
            imagePullPolicy: Always
            args: ["DatabaseInstance3","DataHouseKeepingSproc"]
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
```

- Also, we have an `appsettings template file` that keeps secrets and connection strings from the key vault. We designed this template file in a way that it holds every information so that each running cronjob will perform its job with single deployment to the `k8s` cluster.

```
	{
	"DatabaseInstance1": {
		"Database": "{ConnectionStringTemplate}",
		"HouseKeepingUserPwd": "{HouseKeepingUserPwd}",
		"IndexHouseKeepingSproc": "[HouseKeeping].[IndexStoredProc]"
	},
	"DatabaseInstance2": {
		"Database": "{ConnectionStringTemplate}",
		"HouseKeepingUserPwd": "{HouseKeepingUserPwd}",
		"DataHouseKeepingSproc": "[HouseKeeping].[DataStoredProc]",
		"IndexHouseKeepingSproc": "[HouseKeeping].[IndexStoredProc]"
	},
	"DatabaseInstance3": {
		"Database": "{ConnectionStringTemplate}",
		"HouseKeepingUserPwd": "{HouseKeepingUserPwd}",
		"IndexHouseKeepingSproc": "[HouseKeeping].[IndexStoredProc]",
		"DataHouseKeepingSproc": "[HouseKeeping].[DataStoredProc]"
	},
	"BlobStorageConnectionString": "{Blob-SasUriString}",
	"BlobStorageContainerName": "{Blob-Container}"
	}
``` 