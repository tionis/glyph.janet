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

(defn- get-ref-path [ref]
  (def collection (collections/get (ref :ref)))
  (if collection (collection :path) (util/arch-dir)))

(defn sync
  "synchronize glyph archive"
  []
  (let [scripts-result (scripts/pre-sync)]
    (if (scripts-result :error)
      (error (string/format "%j" scripts-result))))
  (git/loud (util/arch-dir) "fetch" "--all" "--jobs" (string (length (string/split "\n" (git/exec-slurp (util/arch-dir) "remote")))))
  (each ref (git/refs/status/short (util/arch-dir))
    (case (ref :status)
      :both (do (def path (get-ref-path ref))
                (git/pull path)
                (git/push path :ensure-pushed true))
      :ahead (git/push (get-ref-path ref) :ensure-pushed true)
      :behind (git/pull (get-ref-path ref))
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
