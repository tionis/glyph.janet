(import spork/tasker)
(import spork/path)
(import ./util)

(def min-priority "Minimum allowed priority (lower priority tasks will execute first)" 0)
(def max-priority "Maximum allowed priority (lower priority tasks will execute first)" 9)
(def default-priority "Default task priority" 4)
(def default-expiration "Default expiration time (1 day)" (* 30 24 3600))
(def default-task-directory "Default location of task records" "./tasks")

(defn- create-tasker []
  (def tasker-dir (path/join (util/arch-dir) ".git" "tasker"))
  (if (not (os/stat tasker-dir)) (os/mkdir tasker-dir))
  (setdyn :tasker (tasker/new-tasker tasker-dir)))

(defn- ensure-tasker []
  (if (not (dyn :tasker))
      (create-tasker)))

(defn add [args &named note priority qname timeout expiration input]
  (ensure-tasker)
  (default note "")
  (default priority default-priority)
  (assert (and (int? priority) (>= priority min-priority) (<= priority max-priority)) "invalid priority")
  (default qname :default)
  (default expiration default-expiration)
  (tasker/queue-task (dyn :tasker) args note priority qname timeout expiration input))

(defn exec []
  (ensure-tasker)
  (tasker/run-executors (dyn :tasker)))
