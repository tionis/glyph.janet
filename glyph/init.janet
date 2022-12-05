#!/bin/env janet
(import spork :prefix "")
(import ./glob :export true)
(import ./util :export true)
(import ./git :export true)
(import ./store :prefix "" :export true)
(import ./modules :prefix "" :export true)
(import ./scripts :export true)
(import ./daemon :export true)

(defn sync
  "synchronize glyph archive"
  []
  (git/pull (util/arch-dir))
  # TODO 2.0 execute sync for glyph modules
  (scripts/sync/exec)
  (git/push (util/arch-dir) :ensure-pushed true)
  (spit (path/join (util/arch-dir) ".git" "sync.status") (git/exec-slurp (util/arch-dir) "log" "@{u}..")))

(defn fsck []
  # TODO 2.0 execute fsck on modules supporting fsck
  (def arch-dir (util/arch-dir))
  (print "Starting normal recursive git fsck...")
  (git/fsck arch-dir)
  (print)
  (each name (modules/ls)
    (def module (modules/get name))
    (def info-path (path/join arch-dir (module :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (index-of "fsck" (info "supported"))
                (do (print "Starting additional fsck for  " name)
                    (modules/execute name ["fsck"])))))))
