---
layout: post
title: Design decisions and problems faced with during database housekeeping operations
---

In this post, you can find 2 scenarious that explain how selected partition key affects unique constraints defined for your partitioned tables. You have to be careful while designing your partitioning especially if you have unique constraints.

## Unique Constraints in Partitioned Tables

In order to get better understanding about the concept, lets inspect 2 cases. One of them will be straightforward to handle, the other one more complex. 

1. Selecting Proper Column As Partition Key

- If you have table structure similar to the below one and you want to partition your table according to month, then you should compute your partition key with a selected `DateTime` column. So, at first look, it is very reasonable to tahe `createdTime` column into account to computation. Since when the record is inserted to the table, it will be automatically placed on the correct partition. However, there is a unique combined index on table which contraints it as there cannot be more than one record with the same (partitionKey, name, startTime, endTime) combination in same partition. If we choose, createdTime as our partition key then it is guaranteed that this combination is unique in each partition but other partitions can have the same combination as well. So, it violates our unique constraint. To overcome this problem, it is better to choose endTime column for computation of a partition key so that (name, startTime, endTime) combination can be unique across whole table. We have faced with the similar scenario in one of our projects and that is how we managed to resolve it.

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
```

2. Ensure Uniqueness with `DML Trigger`

- Again same scenario with above,  we are trying to ensure uniqueness on our partitioned table but the table structure is similar to the below one. We can choose partition key as DateCreated column. Actually, there is no another column that we can choose other than DateCreated column since it is the only column that has `DateTime` type values.

```
	CREATE TABLE [MySchema].[MyTableName] 
	(
		[Id] BIGINT NOT NULL IDENTITY(1,1),
		[SpecificId] NVARCHAR(40) NOT NULL,
		[DateCreated] DATETIME NOT NULL DEFAULT (GETUTCDATE()),
		[PartitionKey] AS (DATEPART(YEAR, [DateCreated]) * 100
							+ DATEPART(MONTH, [DateCreated])) PERSISTED NOT NULL
	) ON [MyPSMonth]([PartitionKey]);
	GO

	CREATE UNIQUE NONCLUSTERED INDEX [MyUniqueIndex] 
		ON [MySchema].[MyTableName] ([PartitionKey], [SpecificId]);
	GO
```

- So, at first it can be seen as a straightforward task. However, the table also has a unique index on some `SpecificId` column. By applying partitioning without considering this fact results in violating uniqueness of SpecificId. It is just ensured that SpecificId is unique on each partition but there can be records with same SpecificId value on different partitions. So, it is not desired by design. As you can see, the same thing happened for above scenario. But, we had another `DateTime` field in key constraint and we used it in a partition key computation. We choose endTime rather than createdTime column and it was resolved. But we cannot apply the same solution for this scenario since we don't have any other option other than DateCreated column. In order to overcome this problem, we can define a `DML` trigger that will be triggered everytime a new record is intented to be inserted. So, first it is better to explain this trigger.

```
	CREATE TRIGGER [MySchema].[MyTrigger]
	ON [MySchema].[MyTable]
	INSTEAD OF INSERT
	AS
	BEGIN
		SET NOCOUNT ON;
		SET XACT_ABORT ON;

		DECLARE @SpecificId NVARCHAR(40) = NULL,
				@MessageText NVARCHAR(200)	= '',
				@MessageNumber INT			= 0,
				@MessageState	INT			= 0;

		SELECT
			TOP 1 @SpecificId = T.[SpecificId]
		FROM [inserted] I INNER JOIN [MySchema].[MyTable] T ON I.[SpecificId] = T.[SpecificId];

		IF (@SpecificId IS NOT NULL)
		BEGIN
			SET @MessageText = 'The SpecificId with value ' + @SpecificId + ' does already exist in table ' + '[MySchema].[MyTable]';

			SET @MessageState = 1;
			SET @MessageNumber=50102;

			Throw @MessageNumber =	@MessageNumber,
				  @MessageText	 =	@MessageText,
				  @MessageState	 =	@MessageState;
		END

		ELSE
		BEGIN
			INSERT INTO [MySchema].[MyTable]
					(
						[SpecificId],
						[DateCreated]
					)
					SELECT
						[SpecificId],
						[DateCreated]
					FROM [inserted];

			SELECT [inserted].[Id] FROM [inserted] WHERE @@ROWCOUNT > 0 AND [inserted].[Id] = scope_identity();
		END
	END
```
- Basically, this trigger first checks if there is any record with same SpecificId present in whole table before inserting new ones. Note that, we are joining inserted and target table rather than just selecting from target table. The reason is, there can be `bulk insert` situations in the future. If there is no duplicated SpecificId, then it is safe to insert. Otherwise, just throw an exception. In fact, this trigger decreases performance but since we do not have any other option to ensure uniqueness and there is an index on SpecificId column, performance is not a first priority. There is another interesting point in this trigger definition which is the line:

```
		SELECT [inserted].[Id] FROM [inserted] WHERE @@ROWCOUNT > 0 AND [inserted].[Id] = scope_identity();
```
- When insert is tested manually through `SSMS` everything works, nothing wrong. But, while related application is trying to insert records to the table by using `EF Core`, the trigger did not work. The reason to this bug is, `EF Core` throws [DbUpdateConcurrencyException](https://github.com/aspnet/EntityFrameworkCore/issues/12064) when entities do not have IdentityColumn thats primary key. And also `EF Core` only cares about latest inserted identity column value, we have to add the [final line of code](https://stackoverflow.com/questions/26896652/) in order it to be worked with `EF Core` as well.