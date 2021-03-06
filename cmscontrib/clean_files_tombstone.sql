-- This script will replace all the executables with the tombstone, and then
-- will delete all orphan fsobjects and large objects. Run it as follows:
--    psql -tq -U username database < clean_files_tombstone.sql
CREATE OR REPLACE FUNCTION print_table_size(tbl VARCHAR, pref VARCHAR) RETURNS VOID AS $$
DECLARE
    table_size VARCHAR;
BEGIN
    SELECT pg_size_pretty(pg_table_size(tbl)) INTO table_size;
    RAISE NOTICE '%: %', pref, table_size;
END
$$ LANGUAGE plpgsql;

SELECT * FROM print_table_size('pg_largeobject', 'Large objects size');

BEGIN;
    CREATE OR REPLACE FUNCTION do_cleanup_bogus() RETURNS VOID AS $$
    DECLARE
        affected_rows INTEGER;
        deleted_files INTEGER;
    BEGIN
        UPDATE executables SET digest = 'x' WHERE digest != 'x';
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        RAISE NOTICE '% executables were made bogus', affected_rows;
        CREATE TEMPORARY TABLE digests_to_delete (digest VARCHAR) ON COMMIT DROP;
        INSERT INTO digests_to_delete
            SELECT digest FROM fsobjects EXCEPT (
                SELECT digest FROM attachments UNION
                SELECT digest FROM executables UNION
                SELECT digest FROM files UNION
                SELECT digest FROM managers UNION
                SELECT digest FROM printjobs UNION
                SELECT digest FROM statements UNION
                SELECT input AS digest FROM testcases UNION
                SELECT output AS digest FROM testcases UNION
                SELECT input AS digest FROM user_tests UNION
                SELECT digest FROM user_test_executables UNION
                SELECT digest FROM user_test_files UNION
                SELECT digest FROM user_test_managers UNION
                SELECT output AS digest FROM user_test_results);
        GET DIAGNOSTICS affected_rows = ROW_COUNT;
        RAISE NOTICE '% files to be deleted', affected_rows;
        SELECT SUM(rm.success) AS "Files deleted" FROM (
            SELECT lo_unlink(loid) AS success FROM fsobjects WHERE digest IN (
                SELECT digest FROM digests_to_delete
            ) UNION ALL SELECT 0) AS rm INTO deleted_files;
        DELETE FROM fsobjects WHERE digest in (
            SELECT digest FROM digests_to_delete
        );
        RAISE NOTICE '% files were deleted', deleted_files;
    END;
    $$ LANGUAGE plpgsql;
    SELECT * FROM do_cleanup_bogus();
COMMIT;
VACUUM FULL pg_largeobject;
SELECT * FROM print_table_size('pg_largeobject', 'Large objects size');
