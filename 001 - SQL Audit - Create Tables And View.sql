/*
------------------------------------------------------------------------------------------------------
Author:			Datasmith, Richard Grieveson
Date:			23/04/2014 - 29/08/2017
Version:		3.11
Description:	Creates tables and views necessary for SQL Audit.  Note, for safety will not drop if they already exist.

				AuditHeader			Will store one record per record changed.
				AuditLine			Will store one record per field changed.
				AuditTrackedTable	Which tables are tracked. Needs editing after creation (then re-run this procedure)
				v_AuditHeaderLine	Joins AuditHeader and Audit Line for easy consumption.

Change History:	30/10/2015 - Richard Grieveson - Generic version for sharing
				01/11/2016 - Richard Grieveson - Make collation proof
				29/08/2017 - Richard Grieveson - Move to GitHub
------------------------------------------------------------------------------------------------------
*/

/*
DROP TABLE [AuditLine]
DROP TABLE [AuditHeader]
DROP TABLE [AuditTrackedTable]
DROP VIEW  [v_Audit]
*/

--Audit triggers rely on 3 audit tables being present, so create if necessary
IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditHeader]') AND type in (N'U'))
BEGIN

	--Audit Header
	CREATE TABLE [dbo].[AuditHeader]
	(

		 [AuditHeaderID] [uniqueidentifier] NOT NULL PRIMARY KEY		
		,[AuditDate] [datetime] NULL
		,[AuditBy] [VARCHAR] (200) NULL
		,[ActionType] [char](1) NULL
		,[TableName] [varchar](128) NULL
		,[PrimaryKeyField] [varchar](128) NULL
	)

	--Audit Lines
	CREATE TABLE [dbo].[AuditLine]
	(
		 [AuditLineID] [uniqueidentifier] NOT NULL PRIMARY KEY
		,[AuditHeaderID] [uniqueidentifier] NOT NULL
		,[PrimaryKeyValue] [varchar](50) NULL
		,[FieldName] [varchar](128) NULL
		,[DataType] [varchar] (50) NULL
		,[ColumnPosition] [INT] NULL
		,[OldValue] [varchar](max) NULL
		,[NewValue] [varchar](max) NULL
		,[OldForeignKeyValue] [varchar](max) NULL
		,[NewForeignKeyValue] [varchar](max) NULL
	)

	--Cascade delete Foreign Key
	ALTER TABLE [AuditLine]  WITH CHECK ADD  CONSTRAINT [FK_AuditLine_AuditHeader] FOREIGN KEY([AuditHeaderID])
	REFERENCES  [AuditHeader] ([AuditHeaderID]) ON DELETE CASCADE

	ALTER TABLE [dbo].[AuditLine] CHECK CONSTRAINT [FK_AuditLine_AuditHeader]


	 Print '--------------------------------------------------------------------------------------'
	 Print 'Audit data tables created'
	 Print '--------------------------------------------------------------------------------------'
 
END



IF  NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[AuditTrackedTable]') AND type in (N'U'))
BEGIN

	CREATE TABLE [AuditTrackedTable]
	(
		[AuditTrackedTableID] [uniqueidentifier] NOT NULL primary key
		,[TableName] [varchar](200) NOT NULL
		,[RecordDescriptionExpression] [varchar](200) NOT NULL
		,[AuditInsert] [bit] NOT NULL CONSTRAINT [DF_VIT_AUT_AUDIT_TRACKED_TABLES_AUT_AUDIT_INSERT]  DEFAULT ((0))
		,[AuditUpdate] [bit] NOT NULL CONSTRAINT [DF_VIT_AUT_AUDIT_TRACKED_TABLES_AUT_AUDIT_UPDATE]  DEFAULT ((0))
		,[AuditDelete] [bit] NOT NULL CONSTRAINT [DF_VIT_AUT_AUDIT_TRACKED_TABLES_AUT_AUDIT_DELETE]  DEFAULT ((0))
	 )

	 Print '--------------------------------------------------------------------------------------'
	 Print 'Audit Table Tracking table created'
	 Print '--------------------------------------------------------------------------------------'
 
END


IF NOT EXISTS (SELECT * FROM sys.views WHERE object_id = OBJECT_ID(N'[dbo].[v_Audit]'))
BEGIN
EXEC dbo.sp_executesql @statement = N'

CREATE VIEW [dbo].[v_Audit]
AS
SELECT	 
			 h.[AuditHeaderID]
			,h.[AuditDate]
			,h.[AuditBy]
			,h.[ActionType]
			,h.[TableName]
			,h.[PrimaryKeyField]
			,l.[AuditLineID]
			,l.[PrimaryKeyValue]
			,l.[FieldName]
			,l.[DataType]
			,l.[ColumnPosition]
			,l.[OldValue]
			,l.[NewValue]
			,l.[OldForeignKeyValue]
			,l.[NewForeignKeyValue]
FROM		[dbo].[AuditHeader] h
INNER JOIN	[dbo].[AuditLine] l
ON			h.[AuditHeaderID] = l.[AuditHeaderID]

' 


	 Print '--------------------------------------------------------------------------------------'
	 Print 'Audit View created'
	 Print '--------------------------------------------------------------------------------------'


END

GO




