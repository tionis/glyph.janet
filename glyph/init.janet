#!/bin/env janet
(import spork :prefix "")
(import ./glob :export true)
(import ./util :export true)
(import ./git :export true)
(import ./store :prefix "" :export true)
(import ./collections :prefix "" :export true)
(import ./scripts :export true)
(import ./daemon :export true)

### Legacy Support ###
(defn modules/execute [name args] (collections/execute name args))

(defn sync
  "synchronize glyph archive"
  []
  (let [scripts-result (scripts/pre-sync)]
    (if (scripts-result :error)
      (error (string/format "%j" scripts-result))))
  (git/loud (util/arch-dir) "fetch" "--all" "--jobs" (string (length (string/split "\n" (git/exec-slurp (util/arch-dir) "remote")))))
  (each ref (git/refs/status (util/arch-dir))
    (case (ref :status)
      :both (do (def path ((collections/get (ref :ref)) :path))
                (git/pull path)
                (git/push path :ensure-pushed true))
      :ahead (git/push ((collections/get (ref :ref)) :path) :ensure-pushed true)
      :behind (git/pull ((collections/get (ref :ref)) :path))
      :up-to-date :noop
      (error "unknown ref status")))
  (collections/sync)
  (scripts/post-sync))

(defn fsck []
  (def arch-dir (util/arch-dir))
  (print "Starting normal recursive git fsck...")
  (git/fsck arch-dir)
  (print)
  (collections/fsck))
