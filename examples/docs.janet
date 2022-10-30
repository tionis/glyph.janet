#!/bin/env janet
(use glyph/helpers)

(defn cli/help []
  (print `Available Subcommands:
           help - show this help
           search $optional-search-term - search across the cached files and open the result
           shell - $optional_submodule - open a shell in the submodule in root (.)`))

(defn cli/search [search-term]
  (os/execute ["bash" ".search.sh" search-term] :p))

(defn cli/nested-module [args]
  (def prev (os/cwd))
  (git/async prev "pull")
  (os/cd "nested-module")
  (os/execute [".main" ;args])
  (os/cd prev)
  (if ((git/changes (os/cwd)) "studip")
    (do (git/loud prev "add" "studip")
        (git/loud prev "commit" "-m" "nested-module")
        (git/async prev "push"))))

(defn main [myself & args]
  (case (first args)
    "search" (cli/search (string/join (slice args 1 -1) ""))
    "studip" (cli/studip (slice args 1 -1))
    "shell" (shell (os/cwd) (slice args 1 -1))
    "sync" (generic/sync)
    "fsck" (generic/fsck)
    "setup" (generic/setup)
    "help" (cli/help)
    (cli/help)))
