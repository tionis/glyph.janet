(use spork)
(import ./util)

(defn get-socket-path [] (path/join (util/arch-dir) ".git" "glyph-daemon.socket"))
(defn client [] (rpc/client :unix get-socket-path))

(defn check
  "check wether a functional daemin is running and return true if it does"
  []
  (try
    (with [client (client)]
      (if (= (:ping client) :pong)
        true
        false))
    ([err] false)))

(defn sync/enable
  "enabled the daemon sync"
  []
  (with)
  # TODO set config option
  # TODO send command to daemon if running
  )

(defn sync/disable
  "disables the daemon sync"
  []
  # TODO set config option
  # TODO send command to daemon if running
  )

(defn sync/status
  "returns the status of the daemon sync option as boolean"
  []
  # TODO query the sync option
  )

(defn add-job
  [args &named note priority qname timeout expiration input]
  (def client (client))
  (:add-job client args note priority qname timeout expiration input)
  (:close client))

####### Daemon funcs #######

# TODO allow adding jobs
# TODO launch in background automatically
# TODO support jobs interface
# TODO also add sync support to daemon for setups with no automatic cron/systemd based sync

(def- min-priority "Minimum allowed priority (lower priority tasks will execute first)" 0)
(def- max-priority "Maximum allowed priority (lower priority tasks will execute first)" 9)
(def- default-priority "Default task priority" 4)
(def- default-expiration "Default expiration time (1 day)" (* 30 24 3600))
(def- default-task-directory "Default location of task records" "./tasks")

(defn- create-tasker []
  (def tasker-dir (path/join (util/arch-dir) ".git" "tasker"))
  (if (not (os/stat tasker-dir)) (os/mkdir tasker-dir))
  (setdyn :tasker (tasker/new-tasker tasker-dir)))

(defn- ensure-tasker []
  (if (not (dyn :tasker))
      (create-tasker)))

(defn- daemon-add-job [args &named note priority qname timeout expiration input]
  (ensure-tasker)
  (default note "")
  (default priority default-priority)
  (assert (and (int? priority) (>= priority min-priority) (<= priority max-priority)) "invalid priority")
  (default qname :default)
  (default expiration default-expiration)
  (tasker/queue-task (dyn :tasker) args note priority qname timeout expiration input))

(defn- cleanup [])

(defn- shutdown []
  (try
    (do (cleanup) (os/exit 0))
    ([err] (pp {:error err}) (os/exit 1))))

(defn- exec []
  (ensure-tasker)
  (tasker/run-executors (dyn :tasker)))

(defn sync/enable
  "enabled the daemon sync"
  []
  # TODO set config option
  # TODO send command to daemon if running
  )

(defn sync/disable
  "disables the daemon sync"
  []
  # TODO set config option
  # TODO send command to daemon if running
  )

(defn sync/status
  "returns the status of the daemon sync option as boolean"
  []
  # TODO query the sync option
  )

(defn launch []
  (ensure-tasker)
  (rpc/server
    {:sync/status sync/status
     :sync/disable sync/disable
     :sync/enable sync/enable
     :shutdown shutdown
     :sync (fn [x] x)
     :add-job daemon-add-job
     :ping (fn [] :pong)}
    :unix (get-socket-path)))

(defn ensure
  `ensure that a functioning daemon is running in the background
  checks wether a daemon is running and starts a new one if not`
  []
  (if (not check) (launch)))
