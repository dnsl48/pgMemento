-- SCHEMA.sql
--
-- Author:      Felix Kunde <felix-kunde@gmx.de>
--
--              This script is free software under the LGPL Version 3
--              See the GNU Lesser General Public License at
--              http://www.gnu.org/copyleft/lgpl.html
--              for more details.
-------------------------------------------------------------------------------
-- About:
-- This script contains the database schema of pgMemento.
--
-------------------------------------------------------------------------------
--
-- ChangeLog:
--
-- Version | Date       | Description                                       | Author
-- 0.6.2     2019-02-27   comments for tables and columns                     FKun
-- 0.6.1     2018-07-23   schema part cut from SETUP.sql                      FKun
--

/**********************************************************
* C-o-n-t-e-n-t:
*
* PGMEMENTO SCHEMA
*   Addtional schema that contains the log tables and
*   all functions to enable versioning of the database.
*
* TABLES:
*   audit_column_log
*   audit_table_log
*   row_log
*   table_event_log
*   transaction_log
*
* INDEXES:
*   column_log_column_idx
*   column_log_range_idx
*   column_log_table_idx
*   row_log_audit_idx
*   row_log_changes_idx
*   row_log_event_idx
*   table_event_log_unique_idx
*   table_log_idx
*   table_log_range_idx
*   transaction_log_date_idx
*   transaction_log_session_idx
*   transaction_log_txid_idx
*
* SEQUENCES:
*   audit_id_seq
*
***********************************************************/
DROP SCHEMA IF EXISTS pgmemento CASCADE;
CREATE SCHEMA pgmemento;

-- transaction metadata is logged into the transaction_log table
DROP TABLE IF EXISTS pgmemento.transaction_log CASCADE;
CREATE TABLE pgmemento.transaction_log
(
  id SERIAL,
  txid BIGINT NOT NULL,
  stmt_date TIMESTAMP WITH TIME ZONE NOT NULL,
  process_id INTEGER,
  user_name TEXT,
  client_name TEXT,
  client_port INTEGER,
  application_name TEXT,
  session_info JSONB
);

ALTER TABLE pgmemento.transaction_log
  ADD CONSTRAINT transaction_log_pk PRIMARY KEY (id);

COMMENT ON TABLE pgmemento.transaction_log IS 'Stores metadata about each transaction';
COMMENT ON COLUMN pgmemento.transaction_log.id IS 'The Primary Key';
COMMENT ON COLUMN pgmemento.transaction_log.txid IS 'The internal transaction ID by PostgreSQL (can cycle)';
COMMENT ON COLUMN pgmemento.transaction_log.stmt_date IS 'Stores the result of transaction_timestamp() function';
COMMENT ON COLUMN pgmemento.transaction_log.process_id IS 'Stores the result of pg_backend_pid() function';
COMMENT ON COLUMN pgmemento.transaction_log.user_name IS 'Stores the result of current_user function';
COMMENT ON COLUMN pgmemento.transaction_log.client_name IS 'Stores the result of inet_client_addr() function';
COMMENT ON COLUMN pgmemento.transaction_log.client_port IS 'Stores the result of inet_client_port() function';
COMMENT ON COLUMN pgmemento.transaction_log.application_name IS 'Stores the output of current_setting(''application_name'')';
COMMENT ON COLUMN pgmemento.transaction_log.session_info IS 'Stores any infos a client/user defines beforehand with set_config';

-- event on tables are logged into the table_event_log table
DROP TABLE IF EXISTS pgmemento.table_event_log CASCADE;
CREATE TABLE pgmemento.table_event_log
(
  id SERIAL,
  transaction_id INTEGER NOT NULL,
  op_id SMALLINT NOT NULL,
  table_operation VARCHAR(18),
  table_relid OID NOT NULL
);

ALTER TABLE pgmemento.table_event_log
  ADD CONSTRAINT table_event_log_pk PRIMARY KEY (id);

COMMENT ON TABLE pgmemento.table_event_log IS 'Stores metadata about different kind of events happing during one transaction against one table';
COMMENT ON COLUMN pgmemento.table_event_log.id IS 'The Primary Key';
COMMENT ON COLUMN pgmemento.table_event_log.transaction_id IS 'Foreign Key to transaction_log table';
COMMENT ON COLUMN pgmemento.table_event_log.op_id IS 'ID of event type';
COMMENT ON COLUMN pgmemento.table_event_log.table_operation IS 'Text for of event type';
COMMENT ON COLUMN pgmemento.table_event_log.table_relid IS 'The table''s OID';

-- all row changes are logged into the row_log table
DROP TABLE IF EXISTS pgmemento.row_log CASCADE;
CREATE TABLE pgmemento.row_log
(
  id BIGSERIAL,
  event_id INTEGER NOT NULL,
  audit_id BIGINT NOT NULL,
  changes JSONB
);

ALTER TABLE pgmemento.row_log
  ADD CONSTRAINT row_log_pk PRIMARY KEY (id);

COMMENT ON TABLE pgmemento.row_log IS 'Stores the historic data a.k.a the audit trail';
COMMENT ON COLUMN pgmemento.row_log.id IS 'The Primary Key';
COMMENT ON COLUMN pgmemento.row_log.event_id IS 'Foreign Key to table_event_log table';
COMMENT ON COLUMN pgmemento.row_log.audit_id IS ' The implicit link to a table''s row';
COMMENT ON COLUMN pgmemento.row_log.changes IS 'The old values of changed columns in a JSONB object';

-- liftime of audited tables is logged in the audit_table_log table
CREATE TABLE pgmemento.audit_table_log (
  id SERIAL,
  relid OID,
  schema_name TEXT NOT NULL,
  table_name TEXT NOT NULL,
  txid_range numrange  
);

ALTER TABLE pgmemento.audit_table_log
  ADD CONSTRAINT audit_table_log_pk PRIMARY KEY (id);

COMMENT ON TABLE pgmemento.audit_table_log IS 'Stores information about audited tables, which is important when restoring a whole schema or database';
COMMENT ON COLUMN pgmemento.audit_table_log.id IS 'The Primary Key';
COMMENT ON COLUMN pgmemento.audit_table_log.relid IS 'The table''s OID to trace a table when changed';
COMMENT ON COLUMN pgmemento.audit_table_log.schema_name IS 'The schema the table belongs to';
COMMENT ON COLUMN pgmemento.audit_table_log.table_name IS 'The name of the table';
COMMENT ON COLUMN pgmemento.audit_table_log.txid_range IS 'Stores the transaction IDs when the table has been created and dropped';

-- lifetime of columns of audited tables is logged in the audit_column_log table
CREATE TABLE pgmemento.audit_column_log (
  id SERIAL,
  audit_table_id INTEGER NOT NULL,
  column_name TEXT NOT NULL,
  ordinal_position INTEGER,
  data_type TEXT,
  column_default TEXT,
  not_null BOOLEAN,
  txid_range numrange
); 

ALTER TABLE pgmemento.audit_column_log
  ADD CONSTRAINT audit_column_log_pk PRIMARY KEY (id);

COMMENT ON TABLE pgmemento.audit_column_log IS 'Stores information about audited columns, which is important when restoring previous versions of tuples and tables';
COMMENT ON COLUMN pgmemento.audit_column_log.id IS 'The Primary Key';
COMMENT ON COLUMN pgmemento.audit_column_log.audit_table_id IS 'Foreign Key to pgmemento.audit_table_log';
COMMENT ON COLUMN pgmemento.audit_column_log.column_name IS 'The name of the column';
COMMENT ON COLUMN pgmemento.audit_column_log.ordinal_position IS 'The ordinal position within the table';
COMMENT ON COLUMN pgmemento.audit_column_log.data_type IS 'The column''s data type (incl typemods)';
COMMENT ON COLUMN pgmemento.audit_column_log.column_default IS 'The column''s default expression';
COMMENT ON COLUMN pgmemento.audit_column_log.not_null IS 'A flag to tell, if the column is a NOT NULL column or not';
COMMENT ON COLUMN pgmemento.audit_column_log.txid_range IS 'Stores the transaction IDs when the column has been created and dropped';

-- create foreign key constraints
ALTER TABLE pgmemento.table_event_log
  ADD CONSTRAINT table_event_log_txid_fk
    FOREIGN KEY (transaction_id)
    REFERENCES pgmemento.transaction_log (id)
    MATCH FULL
    ON DELETE CASCADE
    ON UPDATE CASCADE;

ALTER TABLE pgmemento.row_log
  ADD CONSTRAINT row_log_table_fk 
    FOREIGN KEY (event_id)
    REFERENCES pgmemento.table_event_log (id)
    MATCH FULL
    ON DELETE CASCADE
    ON UPDATE CASCADE;

ALTER TABLE pgmemento.audit_column_log
  ADD CONSTRAINT audit_column_log_fk
    FOREIGN KEY (audit_table_id)
    REFERENCES pgmemento.audit_table_log (id)
    MATCH FULL
    ON DELETE CASCADE
    ON UPDATE CASCADE;

-- create indexes on all columns that are queried later
DROP INDEX IF EXISTS transaction_log_date_idx;
DROP INDEX IF EXISTS transaction_log_unique_idx;
DROP INDEX IF EXISTS transaction_log_session_idx;
DROP INDEX IF EXISTS table_event_log_unique_idx;
DROP INDEX IF EXISTS row_log_event_idx;
DROP INDEX IF EXISTS row_log_audit_idx;
DROP INDEX IF EXISTS row_log_changes_idx;
DROP INDEX IF EXISTS table_log_idx;
DROP INDEX IF EXISTS table_log_range_idx;
DROP INDEX IF EXISTS column_log_table_idx;
DROP INDEX IF EXISTS column_log_column_idx;
DROP INDEX IF EXISTS column_log_range_idx;

CREATE INDEX transaction_log_date_idx ON pgmemento.transaction_log USING BTREE (stmt_date);
CREATE UNIQUE INDEX transaction_log_unique_idx ON pgmemento.transaction_log USING BTREE (txid, stmt_date);
CREATE INDEX transaction_log_session_idx ON pgmemento.transaction_log USING GIN (session_info);
CREATE UNIQUE INDEX table_event_log_unique_idx ON pgmemento.table_event_log USING BTREE (transaction_id, table_relid, op_id);
CREATE INDEX row_log_event_idx ON pgmemento.row_log USING BTREE (event_id);
CREATE INDEX row_log_audit_idx ON pgmemento.row_log USING BTREE (audit_id);
CREATE INDEX row_log_changes_idx ON pgmemento.row_log USING GIN (changes);
CREATE INDEX table_log_idx ON pgmemento.audit_table_log USING BTREE (table_name, schema_name);
CREATE INDEX table_log_range_idx ON pgmemento.audit_table_log USING GIST (txid_range);
CREATE INDEX column_log_table_idx ON pgmemento.audit_column_log USING BTREE (audit_table_id);
CREATE INDEX column_log_column_idx ON pgmemento.audit_column_log USING BTREE (column_name);
CREATE INDEX column_log_range_idx ON pgmemento.audit_column_log USING GIST (txid_range);


/***********************************************************
CREATE SEQUENCE

***********************************************************/
DROP SEQUENCE IF EXISTS pgmemento.audit_id_seq;
CREATE SEQUENCE pgmemento.audit_id_seq
  INCREMENT BY 1
  MINVALUE 0
  MAXVALUE 2147483647
  START WITH 1
  CACHE 1
  NO CYCLE
  OWNED BY NONE;
