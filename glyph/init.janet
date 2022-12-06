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
  (collections/sync))

(defn fsck []
  (def arch-dir (util/arch-dir))
  (print "Starting normal recursive git fsck...")
  (git/fsck arch-dir)
  (print)
  (each name (collections/ls)
    (def collection (collections/get name))
    (def info-path (path/join arch-dir (collection :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (index-of "fsck" (info "supported"))
                (do (print "Starting additional fsck for  " name)
                    (collections/execute name ["fsck"])))))))
