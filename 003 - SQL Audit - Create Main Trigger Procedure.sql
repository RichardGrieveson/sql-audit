IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'p_AuditMaintainTriggers')
DROP PROCEDURE [dbo].[p_AuditMaintainTriggers]

GO

CREATE PROCEDURE [dbo].[p_AuditMaintainTriggers] 

/*
------------------------------------------------------------------------------------------------------
Author:			Datasmith, Richard Grieveson
Date:			23/04/2014 - 13/10/2022
Version:		3.12
Description:	Creates triggers for all tables defined in AuditTrackedTable
																			
				To make changes to triggers themselves:

				1. Copy the SQL from an existing audit trigger on an audited table from the first BEGIN to END (inclusive)
				2. Globally replace ' with '' so that the text can be stored correctly in @TriggerSQL below				
				3. Paste into the dynamic sql in the proc below
				4. Run the proc to drop and recreate all procs

To Execute:		[p_AuditMaintainTriggers]

Change History:	30/10/2015 - Richard Grieveson - Generic version for sale
				01/11/2016 - Richard Grieveson - Make collation proof
				29/08/2017 - Richard Grieveson - Move to GitHub
				13/10/2022 - Richard Grieveson - KeyID to KeyId...mismatch would have implications depending on SQL collation
------------------------------------------------------------------------------------------------------
*/

AS
SET NOCOUNT ON
------------------------------------------------------------------------------------------------------
--Declarations and temp tables
------------------------------------------------------------------------------------------------------
Declare @DropTriggerSQL nvarchar(max)
Declare @CreateTriggerSQL nvarchar(max)
Declare @TableName nvarchar(100)
Declare @ExecuteSQL nvarchar(max)
Declare @Message nvarchar(100)
Declare @MyId integer
Declare @Insert bit
Declare @Update bit
Declare @Delete bit
Declare @ForSQL nvarchar(25)

CREATE TABLE #t_audit 
(
[KeyId] [int] IDENTITY(1,1) PRIMARY KEY
,TableName  [nvarchar](200) 
,[DropTriggerSQL] [nvarchar](max) 
,[CreateTriggerSQL] [nvarchar](max)
,[Action] nvarchar (10)
,[Insert] bit
,[Update] bit
,[Delete] bit
,[ForSQL] nvarchar(25)
)

------------------------------------------------------------------------------------------------------
--Populate any missing tables defaulted to no audit
------------------------------------------------------------------------------------------------------
INSERT INTO		dbo.AuditTrackedTable
				(
				 AuditTrackedTableID
				,TableName
				,RecordDescriptionExpression
				,AuditInsert
				,AuditUpdate
				,AuditDelete
				)
SELECT  
				NEWID() AS AuditTrackedTableID
				,s.name AS TableName
				,'' AS RecordDescriptionExpression
				,0 AS AuditInsert
				,0 AS AuditUpdate
				,0 AS AuditDelete
FROM			sysobjects s 
LEFT OUTER JOIN dbo.AuditTrackedTable a
ON				s.name = a.TableName
WHERE			s.xtype = 'U'
AND				s.name NOT IN ('AuditHeader','AuditLine','AuditTrackedTable')
AND				a.TableName IS NULL
ORDER BY		s.name

--Remove any that are orphaned
DELETE 
FROM			AuditTrackedTable
WHERE			TableName NOT IN ( SELECT s.Name from sysobjects s WHERE s.xtype = 'U')

------------------------------------------------------------------------------------------------------
--Check any tables specified have a primary key
------------------------------------------------------------------------------------------------------
SELECT				a.TableName				
INTO				#missing_pks			
FROM				[dbo].[AuditTrackedTable] a
LEFT OUTER JOIN		
					(
					SELECT      CAST (kcu.Column_Name AS NVARCHAR(100)) as Primary_Key_Name
								,tc.Table_Name as Table_Name
					FROM        INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc 
					INNER JOIN  INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu 
					ON          tc.Constraint_Name = kcu.Constraint_Name 
					WHERE       tc.Constraint_Type = 'PRIMARY KEY'
					) inf
ON					inf.Table_Name = a.TableName
WHERE				inf.Primary_Key_Name IS NULL
AND					(CAST(a.AuditInsert AS INTEGER) + CAST(a.AuditUpdate AS INTEGER) + CAST(a.AuditDelete AS INTEGER)) <> 0 --we only care about lack of primary key if they are audited

IF EXISTS (SELECT * FROM #missing_pkS)
BEGIN
	SELECT * FROM #missing_pkS
	RAISERROR ('Primary keys are missing from one or more tables (see results). Please add key or remove table from audit before trying again', 16, 1)
	return
END

------------------------------------------------------------------------------------------------------
--Check for tables with a composite primary key
------------------------------------------------------------------------------------------------------
SELECT				a.TableName				
INTO				#composite_keys			
FROM				[dbo].[AuditTrackedTable] a
INNER JOIN		
					(
					SELECT      tc.Table_Name as Table_Name
					FROM        INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc 
					INNER JOIN  INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu 
					ON          tc.Constraint_Name = kcu.Constraint_Name 
					WHERE       tc.Constraint_Type = 'PRIMARY KEY'
					GROUP BY	tc.Table_Name
					HAVING		COUNT(*) > 1
					) inf
ON					inf.Table_Name = a.TableName
WHERE				(CAST(a.AuditInsert AS INTEGER) + CAST(a.AuditUpdate AS INTEGER) + CAST(a.AuditDelete AS INTEGER)) <> 0 --we only care about lack of primary key if they are audited

IF EXISTS (SELECT * FROM #composite_keys)
BEGIN
	SELECT * FROM #composite_keys
	RAISERROR ('The following tables have composite primary keys and cannot be audited (see results). ', 16, 1)
	return
END

------------------------------------------------------------------------------------------------------
--Check for tables with data types I cannot currently audit
------------------------------------------------------------------------------------------------------
SELECT				a.TableName				
INTO				#unsupported_datatypes
FROM				[dbo].[AuditTrackedTable] a
INNER JOIN		
					(
					SELECT     
								DISTINCT TABLE_NAME as Table_Name 
					FROM        INFORMATION_SCHEMA.COLUMNS   
					WHERE		DATA_TYPE  IN ('varbinary','image','text', 'ntext')
					) inf
ON					inf.Table_Name = a.TableName
WHERE				(CAST(a.AuditInsert AS INTEGER) + CAST(a.AuditUpdate AS INTEGER) + CAST(a.AuditDelete AS INTEGER)) <> 0 --we only care about lack of primary key if they are audited

IF EXISTS (SELECT * FROM #unsupported_datatypes)
BEGIN
	SELECT * FROM #unsupported_datatypes
	RAISERROR ('The following tables have unsupported data types (varbinary, image, text, ntext) and cannot be audited (see results). ', 16, 1)
	return
END

  

------------------------------------------------------------------------------------------------------
--Get the trigger SQL into a variable for dynamic execution
--Note, text surrounded by hash(#) place holders are replaced later
------------------------------------------------------------------------------------------------------
SET @CreateTriggerSQL = 

'CREATE TRIGGER [dbo].[t_Audit#TableName#] ON [dbo].[#TableName#]

/*
------------------------------------------------------------------------------------------------------
Author:			Datasmith, Richard Grieveson
Date:			#CreateDate#
Description:	Audit Trigger created by execution of p_AuditMaintainTriggers. See this proc for details
------------------------------------------------------------------------------------------------------
*/

#ForSQL# 
AS 
SET NOCOUNT ON
BEGIN

------------------------------------------------------------------------------------------------------
--Declarations
------------------------------------------------------------------------------------------------------
DECLARE @TableName nvarchar(50) 
DECLARE @PrimaryKeyField nvarchar(50) 
DECLARE @Type NCHAR(1)
DECLARE @LastModified DATETIME
DECLARE @LastModifiedBy varchar(200)
DECLARE @sql varchar(MAX) 
DECLARE @insertedcasesql varchar(MAX) 
DECLARE @deletedcasesql varchar(MAX) 
Declare @AuditHeaderID uniqueidentifier
Declare @USR_ID as uniqueidentifier
Declare @SYSTEM_USER as varchar(50)


--Date
SET @LastModified = GETDATE() 

--User
SET @LastModifiedBy = (SELECT dbo.[f_AuditGetUser]())

 
CREATE TABLE #c_audit 
(
	 [KeyId] [int] IDENTITY(1,1) PRIMARY KEY 
	,[TableName] [nvarchar](50) COLLATE DATABASE_DEFAULT
	,[FieldName] [nvarchar](100) COLLATE DATABASE_DEFAULT
	,[PrimaryKeyField] [nvarchar](50) COLLATE DATABASE_DEFAULT
	,[DataType]  [nvarchar](50) COLLATE DATABASE_DEFAULT
	,[ColumnPosition] int
	,[LastModified] [DATETIME] 
	,[LastModifiedBy] [nvarchar](50) COLLATE DATABASE_DEFAULT
)

--Basically a copy of the actual audit table, although we store data type as well
CREATE TABLE #a_audit
(
	 [AuditID] [int] PRIMARY KEY IDENTITY(1,1) NOT NULL
	,[ActionType] [char](1) COLLATE DATABASE_DEFAULT NULL
	,[TableName] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[PrimaryKeyField] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[PrimaryKeyValue] [varchar](50) COLLATE DATABASE_DEFAULT NULL
	,[FieldName] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[OldValue] [varchar](max) COLLATE DATABASE_DEFAULT NULL
	,[NewValue] [varchar](max) COLLATE DATABASE_DEFAULT NULL
	,[LastModified] [datetime] NULL 
	,[LastModifiedBy] [varchar](150) COLLATE DATABASE_DEFAULT NULL
	,[DataType] [varchar](50) COLLATE DATABASE_DEFAULT NULL
	,[ColumnPosition] int NULL
	,[ForeignKeyField] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyTable] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyField] [varchar](128) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyOldValue] [varchar](50) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyNewValue] [varchar](50) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyField_Col2] [varchar](200) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyOldValue_Col2] [varchar](max) COLLATE DATABASE_DEFAULT NULL
	,[ReferenceKeyNewValue_Col2] [varchar](max) COLLATE DATABASE_DEFAULT NULL	
)

------------------------------------------------------------------------------------------------------
--Retrieve parameters from system tables
------------------------------------------------------------------------------------------------------
SELECT      @TableName = object_name(parent_obj) 
FROM        sysobjects 
WHERE       id = @@procid

SELECT      @PrimaryKeyField = CAST (kcu.Column_Name AS NVARCHAR(50))
FROM        INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc 
INNER JOIN  INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu 
ON          tc.Constraint_Name = kcu.Constraint_Name 
WHERE       tc.Constraint_Type = ''PRIMARY KEY''
AND         tc.Table_Name = @TableName

------------------------------------------------------------------------------------------------------
--What has been inserted and deleted
------------------------------------------------------------------------------------------------------
SELECT * INTO #i_audit FROM INSERTED
SELECT * INTO #d_audit FROM DELETED

------------------------------------------------------------------------------------------------------
--Determine the action type I,U,D
------------------------------------------------------------------------------------------------------
IF EXISTS (SELECT * FROM #i_audit)
begin

   SET @Type = ''I''
    IF EXISTS (SELECT * FROM #d_audit)
      begin
       SET @Type = ''U''
      end  
end 
ELSE
begin
    SET @Type = ''D''
end 


------------------------------------------------------------------------------------------------------
--Write the changes to our temp table type variable
------------------------------------------------------------------------------------------------------
INSERT INTO #c_audit
			(
			 [TableName]
			,[FieldName]
			,[PrimaryKeyField]
			,[DataType]
			,[ColumnPosition]
			)
SELECT     
			 @TableName                    
			,COLUMN_NAME AS Name  
			,@PrimaryKeyField AS PK 
			,DATA_TYPE     
			,ORDINAL_POSITION as ColumnPosition  
FROM        INFORMATION_SCHEMA.COLUMNS   
WHERE       TABLE_NAME = @TableName  
AND			DATA_TYPE NOT IN (''varbinary'',''image'',''text'', ''ntext'')   

------------------------------------------------------------------------------------------------------
--Based on the columns that have changed construct case statements
--These 2 case statements are used in the dynamic sql further below
------------------------------------------------------------------------------------------------------
SET @insertedcasesql = '' ,CASE''
SELECT @insertedcasesql = @insertedcasesql + ''  WHEN FieldName = '' + char(39)+ FieldName + char(39)+ '' THEN  CONVERT(varchar(max), #i_audit.[''+ FieldName + ''], 121)''  FROM #c_audit
SET @insertedcasesql = @insertedcasesql + '' END as NewValue ''
SET @deletedcasesql = Replace(@insertedcasesql,''#i_audit'',''#d_audit'')
SET @deletedcasesql = Replace(@deletedcasesql,''NewValue'',''OldValue'')


------------------------------------------------------------------------------------------------------
--Construct the dynamic SQL 
------------------------------------------------------------------------------------------------------
SET @sql = 
''INSERT INTO      #a_audit 
                  (
				 [ActionType]
				,[TableName]
				,[PrimaryKeyField]
				,[PrimaryKeyValue]
				,[FieldName]
				,[OldValue]
				,[NewValue]
				,[DataType]
				,[ColumnPosition] 
                  )
SELECT      ''
                  + '' CASE 
                           WHEN #i_audit.''  + @PrimaryKeyField + '' IS NULL THEN '' + char(39)+ ''D'' + char(39) 
                          + '' WHEN #d_audit.''  + @PrimaryKeyField + '' IS NULL THEN '' + char(39)+ ''I'' + char(39)
                          + '' ELSE '' + char(39)+ ''U'' + char(39)
                          + '' END  as Type '' 
                  + '','' + char(39)+ @TableName +  char(39)+  '' as TableName ''
                  + '','' + char(39) + @PrimaryKeyField + char(39)+  '' as PrimaryKeyField ''
                  + '',COALESCE(#i_audit.'' + + @PrimaryKeyField + '',#d_audit.'' + @PrimaryKeyField +'') as PrimaryKeyValue ''
                  + '',[FieldName] as FieldName ''
                  + @deletedcasesql 
                  + @insertedcasesql          
                  + '',[DataType] as DataType ''                            
				  + '',[ColumnPosition] as ColumnPosition '' + ''   
FROM              #i_audit
FULL OUTER JOIN   #d_audit
ON                #i_audit.''+ @PrimaryKeyField + '' = #d_audit.'' + @PrimaryKeyField + ''
CROSS JOIN        #c_audit ''

------------------------------------------------------------------------------------------------------
--Execute dymaic SQL to getb data into our temp table
------------------------------------------------------------------------------------------------------
Exec (@sql)

------------------------------------------------------------------------------------------------------
--Delete records that havn''t changed and insert into our actual audit table
------------------------------------------------------------------------------------------------------
DELETE FROM #a_audit WHERE [ActionType] = ''U'' AND IsNull(OldValue,'''') = IsNull(NewValue,'''')				

------------------------------------------------------------------------------------------------------
--Get Foreign Key Data
------------------------------------------------------------------------------------------------------

--Get the foreign key details
UPDATE			 a 
SET				 a.[ForeignKeyField] = f.ColumnName				
				,a.[ReferenceKeyTable] = f.ReferenceTableName				
				,a.[ReferenceKeyField] = f.ReferenceColumnName											
FROM			#a_audit a
INNER JOIN		(
				SELECT		--f.name AS ForeignKey
							--,OBJECT_NAME(f.parent_object_id) AS TableName
							 COL_NAME(fc.parent_object_id,fc.parent_column_id) AS ColumnName			
							,OBJECT_NAME (f.referenced_object_id) AS ReferenceTableName
							,COL_NAME(fc.referenced_object_id,fc.referenced_column_id) AS ReferenceColumnName
				FROM		 sys.foreign_keys AS f
				INNER JOIN	sys.foreign_key_columns AS fc 
				ON			f.OBJECT_ID = fc.constraint_object_id
				INNER JOIN	sys.objects AS o 
				ON			o.OBJECT_ID = fc.referenced_object_id				
				WHERE       OBJECT_NAME(f.parent_object_id) = @TableName
				) f
ON				a.[FieldName] = f.ColumnName


If  (SELECT count(*) FROM #a_audit WHERE [ForeignKeyField] IS NOT NULL) > 0
BEGIN
	--Get the 2nd column from the fk table
	UPDATE a
	SET				[ReferenceKeyField_Col2] = f.ColumnName
	FROM			#a_audit a
	INNER JOIN		(
					SELECT		 TableName as TableName
								,RecordDescriptionExpression as ColumnName
					FROM		AuditTrackedTable
					) f
	ON				f.TableName=a.ReferenceKeyTable



	--Construct dynamic SQL to update the fields we need
	--Old Value
	SELECT @sql = ''''

	SELECT @sql =  @sql + ''UPDATE a SET a.[ReferenceKeyOldValue_Col2]  = (SELECT '' + [ReferenceKeyField_Col2] + '' FROM '' + [ReferenceKeyTable] + '' WHERE '' + [ReferenceKeyField] + '' = '' +  char(39) + [OldValue] +  char(39) + '') FROM #a_audit a  WHERE a.FieldName = '' +  char(39) + [FieldName] +  char(39) + '' AND a.[PrimaryKeyValue] = '' +  char(39) + [PrimaryKeyValue] +  char(39) + '' ; ''	
	FROM			#a_audit
	WHERE			[ForeignKeyField] IS NOT NULL 
	AND				IsNull([ReferenceKeyField_Col2],'''') <> ''''
	
	Exec (@sql)
				
	--New Value
	SELECT @sql = ''''

	SELECT @sql =  @sql + ''UPDATE a SET a.[ReferenceKeyNewValue_Col2]  = (SELECT '' + [ReferenceKeyField_Col2] + '' FROM '' + [ReferenceKeyTable] + '' WHERE '' + [ReferenceKeyField] + '' = '' +  char(39) + [NewValue] +  char(39) + '') FROM #a_audit a  WHERE a.FieldName = '' +  char(39) + [FieldName] +  char(39) + '' AND a.[PrimaryKeyValue] = '' +  char(39) + [PrimaryKeyValue] +  char(39) + '' ; ''			
	FROM			#a_audit
	WHERE			[ForeignKeyField] IS NOT NULL 
	AND				IsNull([ReferenceKeyField_Col2],'''') <> ''''
		
	Exec (@sql)
		
	/*
	--For Testing	
	TRUNCATE TABLE DITCH_TRIGGER
	INSERT INTO DITCH_TRIGGER
	select @sql
	*/

END


------------------------------------------------------------------------------------------------------
--Finally put data into our actual audit tables
------------------------------------------------------------------------------------------------------

SELECT @AuditHeaderID  = NewID()

INSERT INTO [AuditHeader]
(
		 [AuditHeaderID]		
		,[AuditDate]
		,[AuditBy]
		,[ActionType]
		,[TableName]
		,[PrimaryKeyField]
)
SELECT
		 @AuditHeaderID AS [AuditHeaderID]		
		,@LastModified AS [AuditDate]
		,@LastModifiedBy AS [AuditBy]
		,@Type as [ActionType]
		,@TableName as [TableName]
		,@PrimaryKeyField as [PrimaryKeyField]

INSERT INTO [AuditLine]
(
		 [AuditLineID]
		,[AuditHeaderID]
		,[PrimaryKeyValue]
		,[FieldName]
		,[DataType]
		,[ColumnPosition]
		,[OldValue]
		,[NewValue]
		,[OldForeignKeyValue]
		,[NewForeignKeyValue]
)
SELECT
		NewID() AS [AuditLineID]
		,@AuditHeaderID AS [AuditHeaderID]
		,[PrimaryKeyValue] AS [PrimaryKeyValue]
		,[FieldName] AS [FieldName]
		,[DataType] as [DataType]
		,[ColumnPosition] as [ColumnPosition] 
		,[OldValue] AS [OldValue]
		,[NewValue] AS [NewValue]
		,[ReferenceKeyOldValue_Col2] AS [OldForeignKeyValue]
		,[ReferenceKeyNewValue_Col2] AS [NewForeignKeyValue]
FROM	#a_audit

END
'


------------------------------------------------------------------------------------------------------
--List of all tables to which we want to apply the trigger
------------------------------------------------------------------------------------------------------
INSERT INTO #t_audit
(
		 TableName
		,[DropTriggerSQL]
		,[CreateTriggerSQL]
		,[Action]
		,[Insert]
		,[Update]
		,[Delete]
		,[ForSQL]
)
SELECT	s.name as TableName		
		,Replace('IF EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[t_Audit#TableName#]'')) DROP TRIGGER [t_Audit#TableName#]','#TableName#',s.name) as DropTriggerSQL	   
		,Replace(@CreateTriggerSQL,'#TableName#',s.name) as CreateTriggerSQL
		,CASE 
				WHEN	aut.[AuditTrackedTableID] IS NULL THEN 'DROPONLY'
				WHEN	[AuditInsert] = 1 THEN ''
				WHEN    [AuditUpdate] = 1 THEN ''
				WHEN	[AuditDelete] = 1 THEN ''
				ELSE    'DROPONLY'
		End as [Action]
		,IsNull([AuditInsert],0) as [AuditInsert]
		,IsNull([AuditUpdate],0) as [AuditUpdate]
		,IsNull([AuditDelete],0) as [AuditDelete]
		,'FOR' + ' ' as  [ForSQL]
FROM	
				(
				SELECT  s.name
				FROM	sysobjects s 
				WHERE	s.xtype = 'U'
				UNION 
				SELECT		REPLACE(name,'t_Audit','') as name
				FROM		sys.triggers 
				WHERE		name LIKE 't_Audit%' 
				) s
LEFT OUTER JOIN	[AuditTrackedTable] aut
ON				s.name = aut.TableName


------------------------------------------------------------------------------------------------------
--Loop through table executing Drop and Create SQL
------------------------------------------------------------------------------------------------------
SET @MyId = 1

WHILE(EXISTS(SELECT * FROM #t_audit Where KeyId = @MyId))
	BEGIN
		
			--Drop
			SELECT  @ExecuteSQL = DropTriggerSQL 
					,@Message = 'Table: ' + #t_audit.TableName + ' - audit trigger dropped if exists'
			FROM	#t_audit 
			WHERE	KeyId = @MyId
			EXEC (@ExecuteSQL)
			--Print @ExecuteSQL
			Print @Message
			
			SET @ExecuteSQL = ''
			SET @Message = ''
			
			--Create
			SELECT  @ExecuteSQL = CASE WHEN [Action] = 'DROPONLY' THEN '' ELSE CreateTriggerSQL END
					,@Message =   CASE WHEN [Action] = 'DROPONLY' THEN 'Table: ' + #t_audit.TableName + ' - audit trigger NOT created as flagged as not required' ELSE 'Table: ' + #t_audit.TableName + ' - audit trigger created' END
					,@TableName = TableName 
					,@Insert = [Insert]
					,@Update = [Update]
					,@Delete = [Delete]
					,@ForSQL = [ForSQL]
			FROM	#t_audit 
			WHERE	KeyId = @MyId	
			
			--Update SQL depending on whether Insert, Update, Delete
			Declare @comma as nchar(1) = ''
			If @Insert = 1
			BEGIN
				SET @ForSQL = @ForSQL + 'Insert'	
				SET @comma = ','			
			END

			If @Update = 1
			BEGIN
				SET @ForSQL = @ForSQL + @comma + 'Update'		
				SET @comma = ','		
			END

			If @Delete= 1
			BEGIN
				SET @ForSQL = @ForSQL + @comma + 'Delete'		
			END

			SET @ExecuteSQL = Replace(@ExecuteSQL,'#ForSQL#',@ForSQL)

			SET @ExecuteSQL = Replace(@ExecuteSQL,'#CreateDate#',convert(varchar(16),GetDate(),121))
						
			EXEC (@ExecuteSQL)
			--PRINT LEFT(@ExecuteSQL,100)			
			Print @Message
							
			Set @MyId = @MyId + 1
			
			Print ''
	END
	
Print '------------------------------------------------------'		
Print 'All required triggers dropped and created successfully'	
Print '------------------------------------------------------'		

return


