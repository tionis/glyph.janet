#!/bin/env janet
(use glyph/helpers)

(defn cli/help []
  (print `Available Subcommands:
           help - show this help
           search $optional-search-term - search across the cached files and open the result
           shell - $optional_submodule - open a shell in the submodule in root (.)`))

(defn cli/search [search-term]
  (os/execute ["bash" ".search.sh" search-term] :p))

(defn main [myself & args]
  (case (first args)
    "search" (cli/search (string/join (slice args 1 -1) ""))
    "studip" (nested-module "studip" (slice args 1 -1))
    "shell" (shell (os/cwd) (slice args 1 -1))
    "sync" (generic/sync)
    "help" (cli/help)
    (cli/help)))
