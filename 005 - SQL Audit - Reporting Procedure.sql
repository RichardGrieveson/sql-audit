IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'p_AuditGetData')
DROP PROCEDURE [dbo].[p_AuditGetData]

GO

/****** Object:  StoredProcedure [dbo].[p_AuditGetData]    Script Date: 15/08/2016 11:13:32 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[p_AuditGetData]

(
 @DateFrom DATETIME
,@DateTo DATETIME
,@TableName VARCHAR(128)
,@PrimaryKey VARCHAR(100)
,@AuditBy VARCHAR(200)
,@Pivot BIT --Is the result pivoted
)


/*
------------------------------------------------------------------------------------------------------
Author:			Richard Grieveson
Date:			01/11/2016
Description:	
Version			3.02
To Run:			EXEC [p_AuditGetData] 
					    @DateFrom = '2000-01-01'
						,@DateTo = '2100-12-31'
						,@TableName = 'LoginUser'
						,@PrimaryKey = 2
						,@AuditBy = ''
						,@Pivot = 1

						DROP TABLE ##current_pivot
						DROP TABLE ##audit_pivot

Change History:	10/08/2016 - RHG - Creation  
				01/11/2016 - Richard Grieveson - Make collation proof             
------------------------------------------------------------------------------------------------------
*/

AS
SET NOCOUNT ON

------------------------------------------------------------------------------------------------------
--Declarations
------------------------------------------------------------------------------------------------------
DECLARE @PivotColumns VARCHAR(MAX)
DECLARE @SQL VARCHAR(MAX)
Declare @PrimaryKeyField varchar(200)


DECLARE @ColumnsTable TABLE 
		(
		[COLUMN_NAME] VARCHAR(150)
		,[COLUMN_POSITION] INT
		)

IF @TableName IS Null
BEGIN
set @TableName = ''
END

IF @PrimaryKey IS Null
BEGIN
set @PrimaryKey = ''
END

IF @AuditBy IS Null
BEGIN
set @AuditBy = '00000000-0000-0000-0000-000000000000'
END

--They must supply a tablename for the pivot option
IF (@TableName = '' AND @Pivot = 1)
BEGIN
RAISERROR ( 'You must supply @TableName parameter when parameter @Pivot = 0 is specified',16, 1) WITH NOWAIT
RETURN
END

--They must supply a primary for the pivot option
IF (@PrimaryKey = '' AND @Pivot = 1)
BEGIN
RAISERROR ( 'You must supply @PrimaryKey parameter when parameter @Pivot = 0 is specified',16, 1) WITH NOWAIT
RETURN
END


CREATE TABLE #audit
(
 [ActionType] [CHAR](1) COLLATE DATABASE_DEFAULT NOT NULL
,[AuditHeaderID] [UNIQUEIDENTIFIER] NOT NULL
--,[TransactionID] BIGINT NOT NULL
,[AuditDate] [DATETIME] NOT NULL
,[AuditBy] [VARCHAR](200) COLLATE DATABASE_DEFAULT NOT NULL
,[TableName] [VARCHAR](128) COLLATE DATABASE_DEFAULT NOT NULL
,[PrimaryKeyField] [VARCHAR](128) COLLATE DATABASE_DEFAULT NOT NULL
,[PrimaryKeyValue] VARCHAR(MAX) COLLATE DATABASE_DEFAULT NOT NULL
,[FieldName]  [VARCHAR](128) COLLATE DATABASE_DEFAULT NOT NULL
,[DataType] [VARCHAR](50) COLLATE DATABASE_DEFAULT NOT NULL
,[ColumnPosition] [INT] NOT NULL
,[OldValue] VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
,[NewValue] VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
,[OldForeignKeyValue] VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
,[NewForeignKeyValue] VARCHAR(MAX) COLLATE DATABASE_DEFAULT NULL
)

------------------------------------------------------------------------------------------------------
--Insert into temp table
------------------------------------------------------------------------------------------------------

INSERT INTO		 #audit
				(
				 [ActionType]
				,[AuditHeaderID]
				--,[TransactionID] 
				,[AuditDate] 
				,[AuditBy]
				,[TableName] 
				,[PrimaryKeyField]
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
				
				 [ActionType]
				,auh.[AuditHeaderID]
				--,CAST(DATEDIFF(SS, '1970-01-01', [AuditDate]) as bigint) AS [TransactionID]					
				,[AuditDate]
				,[AuditBy]
				,[TableName]				
				,[PrimaryKeyField]
				,[PrimaryKeyValue]
				,[FieldName]
				,[DataType] 
				,[ColumnPosition] 
				,[OldValue]
				,[NewValue]
				,[OldForeignKeyValue] 
				,[NewForeignKeyValue] 
FROM			AuditHeader auh
INNER JOIN		AuditLine aul
ON				auh.AuditHeaderID = aul.AuditHeaderID
WHERE			[AuditDate] BETWEEN @DateFrom AND @DateTo
AND				[TableName] = CASE WHEN @TableName = '' THEN [TableName] ELSE @TableName END
AND				AuditBy = CASE WHEN @AuditBy = '' THEN AuditBy ELSE @AuditBy END
AND				PrimaryKeyValue  = CASE WHEN @PrimaryKey = '' THEN PrimaryKeyValue ELSE @PrimaryKey END



------------------------------------------------------------------------------------------------------
--If we are returning the results as per the audit table (down the page)
------------------------------------------------------------------------------------------------------
IF @Pivot = 0
	BEGIN
		SELECT 
				 [AuditDate]
				,[AuditBy]
				,[TableName]
				,[FieldName]
				,CASE 
					WHEN  [ActionType] = 'D' THEN 'Deleted' 
					WHEN  [ActionType] = 'I' THEN 'Inserted' 
					WHEN  [ActionType] = 'U' THEN 'Updated'  
				END AS [ActionType]
				,[AuditHeaderID]
				--,[TransactionID]																
				,[PrimaryKeyField]
				,[PrimaryKeyValue]				
				,[DataType] 
				--,[ColumnPosition] 
				,[OldValue]
				,[NewValue]
				,[OldForeignKeyValue] 
				,[NewForeignKeyValue] 		
		FROM	#audit
		ORDER BY [AuditDate] DESC, ColumnPosition
	END
ELSE
BEGIN

------------------------------------------------------------------------------------------------------
--If we are returning the results pivoted (across the page)
------------------------------------------------------------------------------------------------------

--Get a list of columns for the table
INSERT INTO		@ColumnsTable (COLUMN_NAME,COLUMN_POSITION)
SELECT     
				COLUMN_NAME AS COLUMN_NAME    
				,ORDINAL_POSITION as COLUMN_POSITION  
FROM			INFORMATION_SCHEMA.COLUMNS   
WHERE			TABLE_NAME = @TableName
AND				DATA_TYPE NOT IN ('varbinary','image','text', 'ntext')  --same restriction as audit trigger


SELECT      @PrimaryKeyField = CAST (kcu.Column_Name AS NVARCHAR(50))
FROM        INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc 
INNER JOIN  INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu 
ON          tc.Constraint_Name = kcu.Constraint_Name 
WHERE       tc.Constraint_Type = 'PRIMARY KEY'
AND         tc.Table_Name = @TableName

SET @PivotColumns = (SELECT STUFF((SELECT  ', ' + CONVERT(VARCHAR(50), COLUMN_NAME)
                                   FROM   @ColumnsTable
								   order by COLUMN_POSITION
                                   FOR XML PATH('')), 1, 2, ''));


--Construct some dynamic sql to get the current  version of the record in question into a single record with correct column names
SELECT @SQL  = 'SELECT '

SELECT     @SQL = @SQL +'IsNull(CONVERT(varchar(max), ['+ COLUMN_NAME + '], 121),'''') COLLATE DATABASE_DEFAULT AS ' + COLUMN_NAME +','
FROM       @ColumnsTable

SELECT @SQL = LEFT(@SQL,LEN(@SQL)-1)

SELECT @SQL = @SQL + ' INTO ##current_pivot FROM ' + @TableName+ ' WHERE ' + @PrimaryKeyField + ' = ''' + @PrimaryKey + ''''
EXEC (@SQL)
--PRINT @SQL


--Pivot the Audit records
SET @SQL = '
SELECT				*					
INTO				##audit_pivot
FROM
					(


					SELECT 							
							*
					FROM   (
							SELECT 
											 [TableName]
											,CASE 
												WHEN  [ActionType] = ''D'' THEN ''Deleted''
												WHEN  [ActionType] = ''I'' THEN ''Inserted'' 
												WHEN  [ActionType] = ''U'' THEN ''Updated''
											 END AS [ActionType]
											,[AuditHeaderID]	
											--,TransactionID as [TransactionID]
											,[AuditDate]
											,AuditBy																						
											,FieldName																					
											--,IsNull([OldValue],'''')  + '' | '' + IsNull([NewValue],'''') as Value																				
											,CASE WHEN [OldForeignKeyValue] IS NULL THEN IsNull([OldValue],'''') ELSE IsNull([OldValue],'''') + '' '' + IsNull([OldForeignKeyValue],'''') END  +  '' > '' + CASE WHEN [NewForeignKeyValue] IS NULL THEN IsNull([NewValue],'''') ELSE IsNull([NewValue],'''') + '' '' + IsNull([NewForeignKeyValue],'''')  END   as Value
							FROM			#audit
							) AS t
					PIVOT	(
							MAX([Value])
							FOR FieldName IN  (#FieldNameList#)
							) AS p 
										
					) t
ORDER BY			AuditDate DESC '



SELECT @SQL = REPLACE(@SQL,'#FieldNameList#',@PivotColumns)
--PRINT @SQL
EXEC(@SQL);


--Get rid of Nulls
SELECT @SQL = ''
SELECT @SQL = @SQL+ 'UPDATE ##audit_pivot SET ' + [COLUMN_NAME]  + ' =  '''' WHERE ' + [COLUMN_NAME] + ' IS NULL;'
FROM	@ColumnsTable
EXEC (@SQL)


SELECT		*
FROM
			(
			SELECT																	
						a.*
			FROM		##audit_pivot a
			
			UNION ALL

			SELECT		
						@TableName AS [TableName]
						,'Current Record' AS [ActionType]
						,'00000000-0000-0000-0000-000000000000' AS [AuditHeaderID]	
						--,0 AS [TransactionID]
						,GETDATE() AS [AuditDate]
						,'' AS [AuditBy]																															
						,c.* 
			FROM		##current_pivot c
			) t
ORDER BY	 [AuditDate] DESC

DROP TABLE ##current_pivot
DROP TABLE ##audit_pivot


END
GO


