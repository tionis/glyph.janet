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

(defn cli/rm [name]) # TODO implement this

(defn cli/add [remote &opt name]
  (default name (first (peg/match ~(* "git@" (thru ":") (capture (any 1))) remote)))
  (if (not remote) (error "could not detect name automatically"))
  (def root (os/cwd))
  (git/loud root "submodule" "add" remote name)
  (git/slurp root "add" name)
  (git/slurp root "commit" "-m" (string "added " name))
  (git/async root "push"))

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

(defn cli/sync [&opt flags]
  (if (and flags (> (length flags) 0))
      (do (error "not implemented yet"))
      (do (print "simple sync")
          (if (not= 0 (os/execute ["git" "pull" "--no-rebase" "--no-edit" "-j8"] :p {"MERGE_AUTOSTASH" "true"})) (error "sync failed during pull"))
          (if (not= 0 (os/execute ["git" "push"] :p)) (error "sync failed during push")))))

(defn get-cached-modules []
  (filter os/dir (map |((string/split " " $0) 1) (string/split "\n" (sh/exec-slurp "git" "config" "--file" ".gitmodules" "--get-regexp" "path")))))

(defn cli/shell [path]
  (def root (os/cwd))
  (git/async root "pull")
  (if path
      (os/cd path)
      (os/cd (jeff/choose "module> " (get-cached-modules) :keywords? true)))
  (def module (path/abspath (os/cwd)))
  (def module-name (misc/trim-prefix (string root "/") module))
  (git/async module "pull")
  # TODO monitor repo and execute git-sync-changes here
  (os/execute [(let [dev_shell_env (os/getenv "DEV_SHELL")] (if dev_shell_env dev_shell_env "bash"))] :p)
  (def new_commits_in_module ((git/changes root) module-name)) # TODO this will trigger for new commits and modified working tree, should only detect new commits
  (def changes_in_module (> (length (git/changes module)) 0))
  #(if changes_in_module (git-sync-changes/async)) # TODO implement this
  (if new_commits_in_module
      (do (git/async module "push")
          (git/slurp root "add" module)
          (git/slurp root "commit" "-m" (string "updated " module-name))
          (git/async root "push"))))

(defn main [myself & args]
  (match args
    ["rm" name] (cli/rm name)
    ["add" remote name] (cli/add remote name)
    ["add" remote] (cli/add remote)
    ["help"] (cli/help)
    ["ls" & patterns] (cli/ls patterns)
    ["shell" path] (cli/shell path)
    ["shell"] (cli/shell nil)
    ["sync" & flags] (cli/sync flags)
    _ (cli/help)))
