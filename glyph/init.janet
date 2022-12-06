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
  # TODO bug!
  # this applies to all refs not only those that have a worktree connected
  # so either silently merge branch in background somehow or use worktrees/list as input insteadof of refs/status/short
  (def worktrees (git/worktree/list (util/arch-dir)))
  (def worktree-map @{})
  (each worktree worktrees (put worktree-map (worktree :branch) (worktree :path)))
  (each ref (git/refs/status/long (util/arch-dir))
    (def path (worktree-map (ref :ref)))
    (if path
      (case (ref :status)
        :both (do (git/pull path)
                  (git/push path :ensure-pushed true))
        :ahead (git/push path :ensure-pushed true)
        :behind (git/pull path)
        :up-to-date :noop
        (error "unknown ref status"))))
  (collections/sync)
  (scripts/post-sync))

(defn fsck []
  (def arch-dir (util/arch-dir))
  (print "Starting normal recursive git fsck...")
  (git/fsck arch-dir)
  (print)
  (collections/fsck))
