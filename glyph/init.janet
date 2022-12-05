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
  # TODO better sync:
  # update all references with `glyph git fetch --all`
  # check which branches need to be merged in (handle submodules)
  # push only if needed
  # add force push that pushes all (including git lfs push --all)
  (git/pull (util/arch-dir))
  (collections/sync)
  (git/push (util/arch-dir) :ensure-pushed true)
  (spit (path/join (util/arch-dir) ".git" "sync.status") (git/exec-slurp (util/arch-dir) "log" "@{u}.."))) # TODO rework this message

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
