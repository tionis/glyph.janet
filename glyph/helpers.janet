(import ./git :export true)
(import spork :prefix "" :export true)
(import jeff/ui :as "jeff" :export true)
(import fzy :export true)
(import ./glob :export true)

(defn shell/root [module-dir &named command]
  (os/cd module-dir)
  (git/pull module-dir :background true)
  (if command
    (os/execute [(os/getenv "SHELL") "-c" command] :p)
    (os/execute [(os/getenv "SHELL")] :p))
  (if (not= (length (git/changes module-dir)) 0)
      (do (git/loud module-dir "add" "-A")
          (git/loud module-dir "commit" "-m" "updated contents manually in shell")))
  (git/push module-dir :background true))

(defn shell/submodule [module-dir submodule &named commit command]
  (os/cd submodule)
  (def submodule-dir (os/cwd))
  (try
    (do (git/current-branch)
        (git/pull module-dir :background true))
    ([err] (print "not pulling submodule due to " err)))
  (if command
    (os/execute [(os/getenv "SHELL") "-c" command] :p)
    (os/execute [(os/getenv "SHELL")] :p))
  (if commit
    (if (> (length (git/changes submodule-dir)) 0)
      (do (git/loud submodule-dir "add" "-A")
          (git/loud submodule-dir "commit" "-m" "updated contents manually in shell"))))
  (if ((git/changes module-dir) submodule) # TODO BUG this does not only detect new commits but also working tree modifications
      (do (git/push submodule-dir :background true)
          (git/loud module-dir "add" submodule)
          (git/loud module-dir "commit" "-m" (string "updated " submodule))
          (git/push module-dir :background true)))

(defn shell [module-dir args &named commit-in-submodules]
  (setdyn :args [module-dir ;args])
  (def res (argparse/argparse "simple shell"
                              "command" {:kind :option
                                         :short "c"
                                         :help "execute command in shell (passed to shell via the -c flag)"}
                              :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (def submodules (array/concat (git/ls-submodule-paths module-dir) ["."]))
  (def selected
    (if (res :default)
        (first (res :default))
        (jeff/choose "select shell path> " submodules)))
  (if (= selected ".")
      (shell/root module-dir :command (res "command"))
      (shell/submodule module-dir selected :command (res "command") :commit commit-in-submodules)))

(defn generic/sync [&named remote]
  (def root (os/cwd))
  (git/pull root :remote remote)
  (git/push root :remote remote :ensure-pushed true))
