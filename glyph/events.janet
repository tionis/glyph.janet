#https://webapp.io/blog/postgres-is-the-answer/
(defn init-db [conn]
  (def create-type "CREATE TYPE ci_job_status AS ENUM ('new', 'initializing', 'initialized', 'running', 'success', 'error');")
  (def create-table
    `CREATE TABLE ci_jobs(
	  id SERIAL NOT NULL PRIMARY KEY,
	  name text NOT NULL,
	  status ci_job_status,
	  status_change_time timestamp,
    payload json NOT NULL
    error text
    );`)
  (def setup-triggers
    `CREATE OR REPLACE FUNCTION ci_jobs_status_notify()
	     RETURNS trigger AS
    $$
    BEGIN
	    PERFORM pg_notify('ci_jobs_status_channel', NEW.id::text);
	    RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;


    CREATE TRIGGER ci_jobs_status
	    AFTER INSERT OR UPDATE OF status
	    ON ci_jobs
	    FOR EACH ROW
    EXECUTE PROCEDURE ci_jobs_status_notify();`)
  (pq/exec))

# (defn send-job [name payload]
#   ())
#
# (def get-next-job []
#   (de
#   UPDATE ci_jobs SET status='initializing'
# WHERE id = (
#   SELECT id
#   FROM ci_jobs
#   WHERE status='new'
#   ORDER BY id
#   FOR UPDATE SKIP LOCKED
#   LIMIT 1
# )
# RETURNING *;)
