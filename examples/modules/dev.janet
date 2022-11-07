#!/bin/env janet
(use spork)
(import glyph/git)
(import jeff/ui :as "jeff")

(defn get-null-file "get the /dev/null equivalent for current platform" []
  (case (os/which)
    :windows "NUL"
    :macos "/dev/null"
    :web (error "Unsupported Operation")
    :linux "/dev/null"
    :freebsd "/dev/null"
    :openbsd "/dev/null"
    :posix "/dev/null"))

(defn cli/rm [name]
  (def root (os/cwd))
  (def path (git/exec-slurp root "config" "-f" ".gitmodules" (string "submodule." name ".path")))
  (git/loud root "submodule" "--quiet" "deinit" "--force" path)
  (sh/rm path)
  (git/loud root "rm" "--cached" "-rfq" path)
  (git/loud root "config" "-f" ".gitmodules" "--remove-section" (string "submodule." name))
  (sh/rm (path/join ".git" "modules" path))
  (git/loud root "add" ".gitmodules")
  (git/loud root "commit" "-m" (string "removed " name " module"))
  (git/push root))

(defn cli/add [remote &opt name]
  (default name (first (peg/match ~(* "git@" (thru ":") (capture (any 1))) remote)))
  (if (not remote) (error "could not detect name automatically"))
  (def root (os/cwd))
  (git/loud root "submodule" "add" remote name)
  (git/loud root "add" name)
  (git/loud root "commit" "-m" (string "added " name))
  (git/push root :background true))

(defn cli/help []
  (print `Available commands:
           rm path - remove the submodule at path
           add remote optional_path - add new submodule at optional_path
           ls optional_patterns - list all submodules matching the optional_patterns
           sync some_flags - synchronize this repo
           help - show this help`))

(defn cli/ls [&opt patterns]
  (if (and patterns (> (length patterns) 0)) (error "not implemented"))
  (each item (map |(string/split " " $0)
                  (string/split "\n"
                                (sh/exec-slurp "git" "config" "--file" ".gitmodules" "--get-regexp" "path")))
    (print (item 1))))

(defn get-cached-modules []
  (filter os/dir (map |((string/split " " $0) 1) (string/split "\n" (sh/exec-slurp "git" "config" "--file" ".gitmodules" "--get-regexp" "path")))))

(defn cli/shell [path]
  (def root (os/cwd))
  (git/pull root :background true)
  (if path
      (os/cd path)
      (os/cd (jeff/choose "module> " (get-cached-modules) :keywords? true)))
  (def module (path/abspath (os/cwd)))
  (def module-name (misc/trim-prefix (string root "/") module))
  (git/pull module :background true)
  # TODO monitor repo and execute git-sync-changes here
  (os/execute [(let [dev_shell_env (os/getenv "DEV_SHELL")] (if dev_shell_env dev_shell_env "bash"))] :p)
  (def new_commits_in_module ((git/changes root) module-name)) # TODO this will trigger for new commits and modified working tree, should only detect new commits
  (def changes_in_module (> (length (git/changes module)) 0))
  #(if changes_in_module (git-sync-changes/async)) # TODO implement this
  (if new_commits_in_module
      (do (git/push module :background true)
          (git/loud root "add" module)
          (git/loud root "commit" "-m" (string "updated " module-name))
          (git/push root :background true))))

(defn main [myself & args]
  (match args
    ["rm" name] (cli/rm name)
    ["add" remote name] (cli/add remote name)
    ["add" remote] (cli/add remote)
    ["help"] (cli/help)
    ["ls" & patterns] (cli/ls patterns)
    ["shell" path] (cli/shell path)
    ["shell"] (cli/shell nil)
    _ (cli/help)))
