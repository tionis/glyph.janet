(import spork/rpc)

# TODO allow adding jobs
# TODO launch in background automatically
# TODO support jobs interface
# TODO also add sync support to daemon for setups with no automatic cron/systemd based sync
(defn sync [])

(defn launch []
  # TODO start a tasker instance in the background
  # TODO start rpc server
  )

(defn check 
  "check wether a functional daemin is running and return true if it does"
  []
  (rpc/client))

(defn ensure 
  `ensure that a functioning daemon is running in the background
  checks wether a daemon is running and starts a new one if not`
  []
  (if (not (check)) (os/execute :t))

(defn cleanup [])

(defn shutdown []
  (try
    (do (cleanup) (os/exit 0))
    ([err] (pp {:error err}) (os/exit 1))))
