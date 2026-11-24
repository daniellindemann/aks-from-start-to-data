-- Usage: sqlcmd -b -v MemberName="id-da-workload" -i remove-sql-permissions.sql
-- Dropping the database user also removes its role memberships and permissions.
IF EXISTS (
    SELECT [name]
    FROM sys.database_principals
    WHERE [name] = '$(MemberName)'
)
BEGIN
    DROP USER [$(MemberName)];
END
