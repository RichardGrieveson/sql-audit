

EXEC [p_AuditMaintainTriggers]

PRINT '--------------------------------------------------------------------------------------'
PRINT 'Now nominate tables to be audited by editing the following fields in AuditTrackedTable'
PRINT ' - AuditInsert'
PRINT ' - AuditUpdate'
PRINT ' - AuditDelete'
PRINT 'You can also define an expression in the field [RecordDescriptionExpression]'
PRINT 'This is used to identify a FK record in the audit table, an example would be:'
PRINT '[FirstName] + [LastName]'
PRINT 'If not defined here the audit returns no data'
PRINT '--------------------------------------------------------------------------------------'

