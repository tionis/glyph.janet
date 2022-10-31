#!/bin/env janet
(import spork :prefix "" :export true)
(import ./util :export true)
(import ./git :export true)
(import ./config :prefix "" :export true)
(import ./modules :export true)
(import ./scripts :export true)

(defn sync
  "synchronize arch specified by config synchroniously"
  []
  # TODO sync all modules
  (os/execute ["git" "-C" (dyn :arch-dir) "pull"] :p)
  (os/execute ["git" "-C" (dyn :arch-dir) "push"] :p))

(defn fsck []
  (os/execute ["git" "-C" (dyn :arch-dir) "fsck"] :p))
