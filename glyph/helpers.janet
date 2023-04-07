(import ./git :export true)
(import spork :prefix "" :export true)
(import jeff :export true)
(import ./glob :export true)

(defn shell/root [module-dir &named command]
  (os/cd module-dir)
  (git/pull module-dir :background true)
  (if command
    (case (type command)
      :function (command)
      :string (os/execute [(os/getenv "SHELL") "-c" command] :p)
      :tuple (os/execute command :p))
    (os/execute [(os/getenv "SHELL")] :p))
  (if (not= (length (git/changes module-dir)) 0)
      (do (git/loud module-dir "add" "-A")
          (git/loud module-dir "commit" "-m" "updated contents manually in shell")))
  (git/push module-dir :background true))

(defn shell/submodule [module-dir submodule &named commit command message]
  (os/cd submodule)
  (def submodule-dir (os/cwd))
  (try
    (do (git/current-branch module-dir)
        (git/pull module-dir :background true))
    ([err] (print "not pulling submodule due to " err)))
  (if command
    (case (type command)
      :function (command)
      :string (os/execute [(os/getenv "SHELL") "-c" command] :p)
      :tuple (os/execute command :p))
    (os/execute [(os/getenv "SHELL")] :p))
  (when (and commit (> (length (git/changes submodule-dir)) 0))
    (git/loud submodule-dir "add" "-A")
    (git/loud submodule-dir "commit" "-m" (if message message "updated contents manually in shell")))
  (when ((git/changes module-dir) submodule) # TODO BUG this does not only detect new commits but also working tree modifications
    (git/push submodule-dir :background true)
    (git/loud module-dir "add" submodule)
    (git/loud module-dir "commit" "-m" (string "updated " submodule)) # TODO BUG this does not trigger a push in the module-dir for some reason
    # TODO hotfix below due to git or gitea error, unsure which one of those exactly
    (git/push module-dir :background true :recurse-submodules false))) # TODO init push in general when there are unpushed changes

(defn shell [module-dir args &named commit-in-submodules command submodule-commit-message]
  (setdyn :args [module-dir ;args])
  (def res (argparse/argparse "simple shell"
                              "command" {:kind :option
                                         :short "c"
                                         :help "execute command in shell (passed to shell via the -c flag)"}
                              "commit-in-submodules" {:kind :flag
                                                      :help "commit automatically in submodules"}
                              "submodule-commit-message" {:kind :option
                                                          :help "commit message in submodules"}
                              :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (def submodules (array/concat (git/ls-submodule-paths module-dir) ["."]))
  (def selected
    (if (res :default)
        (first (res :default))
        (jeff/choose submodules :prmpt "select shell path> ")))
  (if (= selected ".")
      (shell/root module-dir :command (or command (res "command")))
      (shell/submodule module-dir selected
                       :command (or command (res "command"))
                       :commit (or commit-in-submodules (res "commit-in-submodules"))
                       :message (or submodule-commit-message (res "submodule-commit-message")))))

(defn generic/sync [&named remote]
  (def root (os/cwd))
  (git/pull root :remote remote)
  (git/push root :remote remote :ensure-pushed true))

(defn nested-module [module-path args]
  (def prev (os/cwd))
  (git/pull prev :background true)
  (os/cd module-path)
  (os/execute [".main" ;args])
  (os/cd prev)
  (if ((git/changes (os/cwd)) module-path)
    (do (git/loud prev "add" module-path)
        (git/loud prev "commit" "-m" (string "changes in " module-path))
        (git/push prev :background true))))
