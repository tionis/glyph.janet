#!/bin/env janet
(use glyph/helpers)

(defn cli/help []
  (print `Available Subcommands:
           help - show this help
           search $optional-search-term - search across the cached files and open the result
           shell - $optional_submodule - open a shell in the submodule in root (.)
           calibre - start calibre with specified library`))

(defn cli/search [search-term]
  (os/execute ["bash" ".search.sh" search-term] :p))

(defn main [myself & args]
  (case (first args)
    "search" (cli/search (string/join (slice args 1 -1) ""))
    "shell" (shell (os/cwd) (slice args 1 -1))
    "sync" (generic/sync)
    "calibre" (shell (os/cwd) (slice args 1 -1)
                     :commit-in-submodules true
                     :command  "calibre \"--with-library=$(pwd)\""
                     :submodule-commit-message "updated library with calibre")
    "help" (cli/help)
    (cli/help)))
