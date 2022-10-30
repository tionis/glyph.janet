(import ./git :export true)
(import spork :prefix "" :export true)
(import jeff/ui :as "jeff" :export true)

(defn shell/root [module-dir]
  (os/cd module-dir)
  (git/async module-dir "pull")
  (os/execute [(os/getenv "SHELL")] :p)
  (if (not= (length (git/changes module-dir)) 0)
      (do (git/loud module-dir "add" "-A")
          (git/loud module-dir "commit" "-m" "updated contents manually in shell")
          (git/async module-dir "push"))))

(defn shell/submodule [module-dir submodule &named commit]
  (os/cd submodule)
  (def submodule-dir (os/cwd))
  (git/async module-dir "pull")
  # TODO auto pull submodule if a branch is checked out, do nothing when head is detached?
  (os/execute [(os/getenv "SHELL")] :p)
  (if commit
    (if (> (length (git/changes submodule-dir)) 0)
      (do (git/loud "add" "-A")
          (git/loud "commit" "-m" "updated contents manually in shell"))))
  (if ((git/changes module-dir) submodule) # TODO BUG this does not only detect new commits but also working tree modifications
      (do (git/async submodule-dir "push")
          (git/loud module-dir "add" submodule)
          (git/loud module-dir "commit" "-m" (string "updated " submodule))
          (git/async module-dir "push"))))

(defn shell [module-dir args &named commit-in-submodules]
  (def submodules (array/concat (git/ls-submodules module-dir) ["."]))
  (def selected
    (if (> (length args) 0)
        (first args)
        (jeff/choose "select shell path> " submodules)))
  (if (= selected ".")
      (shell/root module-dir)
      (shell/submodule module-dir selected :commit commit-in-submodules)))

# TODO implement these helpers
(defn generic/sync [&opt target])
(defn generic/fsck [])
(defn generic/setup [])
(defn generic/bundle [])
(defn generic/glyph-info [supported-operations]
  (printf "%j" {:supported (if supported-operations supported-operations [:sync :fsck :setup :bundle])}))
