(import ./collections :prefix "")
(import ./scripts)
(import ./git)
(import ./util)

(defn sync
  "synchronize all worktrees in glyph repo"
  []
  (let [scripts-result (scripts/pre-sync)]
    (if (scripts-result :error)
      (error (string/format "%j" scripts-result))))
  (collections/pre-sync)
  (git/loud (util/arch-dir) "fetch" "--all" "--jobs" (string (length (string/split "\n" (git/exec-slurp (util/arch-dir) "remote")))))
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
  (collections/post-sync)
  (let [scripts-result (scripts/post-sync)]
    (if (scripts-result :error)
      (error (string/format "%j" scripts-result)))))
