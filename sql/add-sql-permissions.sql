-- Usage: sqlcmd -v MemberName="id-da-workload" -i add-sql-permissions.sql
IF NOT EXISTS (
    SELECT [name]
    FROM sys.database_principals
    WHERE [name] = '$(MemberName)'
)
BEGIN
    CREATE USER [$(MemberName)] FROM EXTERNAL PROVIDER;
END

ALTER ROLE db_datareader ADD MEMBER [$(MemberName)];
ALTER ROLE db_datawriter ADD MEMBER [$(MemberName)];
ALTER ROLE db_ddladmin ADD MEMBER [$(MemberName)];
