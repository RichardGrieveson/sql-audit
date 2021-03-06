
/****** Object:  UserDefinedFunction [dbo].[f_AuditGetUser]    Script Date: 4/11/2016 3:48:46 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE  FUNCTION [dbo].[f_AuditGetUser]()

RETURNS VARCHAR(200)

/*
------------------------------------------------------------------------------------------------------
Author:			Datasmith, Richard Grieveson
Date:			23/04/2014 - 29/08/2017
Version:		3.11
Description:	
				Gets the user for SQL Audit
				If the UI has passed in the user in the connection string then it uses this.  
				It expects a key value pair like this--> UserName:JohnSmith
				In SSMS you can test with this in addional connection paramgters tab with: Workstation ID=UserName:JohnSmith;				
				If it doesn't find a key value pair in the correct format then it returns the SYSTEM_USER instead
To Execute:		SELECT dbo.[f_AuditGetUser]()
Change History:	10/08/2016 - Richard Grieveson - Generic version for publish to blog
				01/11/2016 - Richard Grieveson - Make collation proof
				04/11/2016 - Richard Grieveson - Make less bonnkers
				29/08/2017 - Richard Grieveson - Move to GitHub
------------------------------------------------------------------------------------------------------
*/ 

AS
BEGIN
------------------------------------------------------------------------------------------------------
--Declarations
------------------------------------------------------------------------------------------------------
DECLARE @KeyValuePairString VARCHAR(210)
DECLARE @UserName NVARCHAR(200) = ''
DECLARE @DomainPosition INTEGER

------------------------------------------------------------------------------------------------------
--Get the key value pair out of host_name param in the connection string
------------------------------------------------------------------------------------------------------
--SELECT @KeyValuePairString = [host_name] FROM sys.dm_exec_sessions WITH (NOLOCK) WHERE session_id = @@SPID
SELECT @KeyValuePairString = [program_name] FROM sys.dm_exec_sessions WITH (NOLOCK) WHERE session_id = @@SPID

------------------------------------------------------------------------------------------------------
--Do some validation before pulling the string to make sure it has been passed in
------------------------------------------------------------------------------------------------------

--If there is a UserName: key then we good to get the name
IF (CHARINDEX('UserName:',@KeyValuePairString) <> 0)
BEGIN
	SELECT @UserName = LTRIM(RTRIM(REPLACE(@KeyValuePairString,'UserName:','')))		
END

--Final check.  If we have no name then return the SQL User
IF @UserName = ''
BEGIN
	SELECT @UserName = 	LEFT(SYSTEM_USER,200)
	
	--Get rid of domain
	SELECT @DomainPosition = CHARINDEX('\',@UserName)
	
	IF @DomainPosition <> 0
	BEGIN
		SELECT @UserName = SUBSTRING(@UserName,@DomainPosition+1,200)
	END

END

RETURN @UserName
--RETURN @KeyValuePairString

END
