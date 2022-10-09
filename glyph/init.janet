#!/bin/env janet
(import flock)
(import chronos :as "date" :export true)
(import spork :prefix "" :export true)
(import uri :export true)
(import ./glob :export true)
#(use ./log-item) # disabled due to being unfinished
(import ./graph :export true)
(import fzy :as "fzy" :export true)
(import jeff/ui :as "jff" :export true)
(import ./markdown :as "md" :export true)
(import ./filesystem :as "fs" :export true)
(import ./util :export true)

# old hack as workaround https://github.com/janet-lang/janet/issues/995 is solved
# will keep this here for future reference
#(ffi/context)
#(ffi/defbind setpgid :int [pid :int pgid :int])
#(ffi/defbind getpgid :int [pid :int])

(def patt-strip-file-ending (peg/compile ~(* (capture (some (* (not ".") 1))) "." (some 1))))

(def patt_metadata_header "PEG-Pattern that captures the content of a metadata header in a markdown file" # TODO improve this pattern, this may have false positives if a string in the header contain \n---\n
  (peg/compile ~(* "---\n" (capture (any (* (not "\n---\n") 1))) "\n---\n")))

(defn dprint "print x formatted like in the repl" [x]
  (printf "%M" x))

(defn get-null-file "get the /dev/null equivalent for current platform" []
  (case (os/which)
    :windows "NUL"
    :macos "/dev/null"
    :web (error "Unsupported Operation")
    :linux "/dev/null"
    :freebsd "/dev/null"
    :openbsd "/dev/null"
    :posix "/dev/null"))

(defn get-default-log-doc "get the default content for a log file given a date as iso-string"
  [date_str]
  (def today (date/from-string date_str))
  (string "# " date_str " - " ((date/week-days :long) (today :week-day)) "\n"
          "[yesterday](" (:date-format (date/days-ago 1 today)) ") <--> [tomorrow](" (:date-format (date/days-after 1 today)) ")\n"
          "\n"
          "## ToDo\n"
          "\n"
          "## Notes\n"))

(defn home []
  (def p (os/getenv "HOME"))
  (if (or (not p) (= p ""))
      (let [userprofile (os/getenv "USERPROFILE")]
           (if (or (not userprofile) (= userprofile ""))
               (error "Could not determine home directory")
               userprofile))
      p))

(defn get-default-arch-dir [] (path/join (home) "arch"))

(defn indexify_dir # TODO check if this still works after the file-id migration
  "transform given dir to index.md based md structure" # TODO also transform non markdown files into their markdown equivalent (probably using the html render function)
  # TODO maybe instead of editing in-place an output tar file could be used?
  [path]
  (let [items (os/dir path)]
    (each item items
      (let [name (util/no-ext item)]
        (if name
            (each item2 items
              (if (= item2 (name 0))
                  (do (fs/copy-file item (path/join "name" "index.md"))
                      (os/rm item)))))))))

(defn indexify_dirs_recursivly
  "transform dirs recursivly to index.md based md structure starting at path"
  [path]
  (fs/scan-directory path (fn [x]
                                    (if (= ((os/stat x) :mode) :directory)
                                        (indexify_dir x)))))

(defn exec-slurp
   "Read stdout of subprocess and return it trimmed in a string." 
   [& args]
   (when (dyn :verbose)
     (flush)
     (print "(exec-slurp " ;(interpose " " args) ")"))
   (def proc (os/spawn args :px {:out :pipe}))
   (def out (get proc :out))
   (def buf @"")
   (ev/gather
     (:read out :all buf)
     (:wait proc))
   (string/trimr buf))

(defn git # TODO put the git handling stuff into its own module
  "given a config and some arguments execute the git subcommand on wiki"
  [config & args]
  (exec-slurp "git" "-C" (config :arch-dir) ;args))

(defn git/loud [config & args] (os/execute ["git" "-C" (config :arch-dir) ;args] :p))

(def git_status_codes
  "a map describing the meaning of the git status --porcelain=v1 short codes"
  {"A" :added
   "D" :deleted
   "M" :modified
   "R" :renamed
   "C" :copied
   "I" :ignored
   "?" :untracked
   "T" :typechange
   "X" :unreadable
   "??" :unknown})

(def patt_git_status_line "PEG-Pattern that parsed one line of git status --porcellain=v1 into a tuple of changetype and filename"
  (peg/compile ~(* (opt " ") (capture (between 1 2 (* (not " ") 1))) " " (capture (some 1)))))

(defn get-changes
  "give a config get the changes in the working tree of the git repo"
  [git-repo-dir]
  (def ret @[])
  (each line (string/split "\n" (git {:arch-dir git-repo-dir} "status" "--porcelain=v1"))
    (if (and line (not= line ""))
      (let [result (peg/match patt_git_status_line line)]
        (array/push ret [(git_status_codes (result 0)) (result 1)]))))
  ret)

# maybe use c wrapper and c code as seen here:
# https://man7.org/tlpi/code/online/book/daemons/become_daemon.c.html
# this may be blocked until https://github.com/janet-lang/janet/issues/995 is solved
(defn git/async
  "given a config and some arguments execute the git subcommand on wiki asynchroniously"
  [config & args]
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (os/spawn ["git" "-C" (config :arch-dir ) ;args] :pd {:out fout :err ferr}))

(defn commit
  "commit staged files, ask user based on config for message, else fallback to default_message"
  [config default_message]
  (if (not (get-in config [:argparse "no-commit"]))
      (if (get-in config [:argparse "ask-commit-message"])
        (do (prin "Commit Message: ")
            (def message (string/trim (file/read stdin :line)))
            (if (= message "")
                (git config "commit" "-m" default_message)
                (git config "commit" "-m" message)))
        (git config "commit" "-m" default_message))))

(def positional_args_help_string
  (string `Command to run or document to open
          If no command or file is given it switches to an interactiv document selector
          Supported commands:
          - ls $optional_path - list all files at path or root if not path was given
          - rm $path - delete document at path
          - mv $source $target - move document from $source to $target
          - search $search_term - search using a regex
          - log $optional_natural_date - edit a log for an optional date
          - lint $optional_paths - lint whole wiki or a list of paths
          - graph - show a graph of the wiki
          - sync - sync the repo
          - git $args - pass args thru to git`))
(defn print_command_help "print help for subcommands" [] (print positional_args_help_string))

(def ls-files-peg
  "Peg to handle files from git ls-files"
  (peg/compile # TODO finish this
    ~{:param (+ (* `"` '(any (if-not `"` (* (? "\\") 1))) `"`)
                (* `'` '(any (if-not `'` (* (? "\\") 1))) `'`)
                (some (if-not "" 1)))
      :main (any (* (capture (any (* (not "\n") 1))) "\n"))}))

(defn is-doc [path]
  (index-of (util/only-ext path)
            [".md"]))

(defn get-files
  "given a config and optional path to begin list all documents in wiki (not assets, only documents)"
  [config &opt path]
  (default path "")
  (def p (path/join (config :wiki-dir) path))
  (if (= ((os/stat p) :mode) :file)
      p
      (map |((peg/match ~(* ,p (? (+ "/" "\\")) (capture (any 1))) $0) 0)
            (filter |(is-doc $0) # TODO migrate away from filesystem.janet
                    (fs/list-all-files p))))) # TODO migration to the inclusion of file endings and using the get-doc-path function to get a full valid wiki path from an ambigous pathless link
  #(peg/match ls-files-peg (string (git config "ls-files")) "\n")) # TODO implement this probably fast ways
  # - maybe use git ls-files as it is faster?
  # - warning: ls-files does not print special chars but puts the paths between " and escapes the special chars -> problem with newlines?
  # - problem: this is a bit more complex and I would have to fix my PEG above to correctly parse the output again

(defn interactive-select
  "let user interactivly select an element of the given array"
  [arr]
  (jff/choose "" arr :keywords? true))

(defn file/select
  "let user interactivly select a file, optionally accepts a files-override for a custom file set and preview-command to show the output of in a side window for the currently selected file"
  [config &named files-override preview-command]
  (def files (map (fn [x] (if (not= (string/find "." x) 0)
                              (util/no-ext x)
                              x))
                  (if files-override files-override (get-files config))))
  (def selected (interactive-select files))
  (if selected (string selected ".md") selected))

(defn rm
  "delete doc specified by path"
  [config file] # TODO check via graph what links are broken by that and warn user, ask them if they still want to continue (do not ask if (get-in config [:argparse "force"]) is true)
  (git config "rm" (string file ".md"))
  (commit config (string "wiki: deleted " file))
  (if (config :sync) (git/async config "push")))

(defn rm/interactive
  "delete document select interactivly"
  [config]
  (def file (file/select config))
  (if file
    (rm config file)
    (print "No file selected!")))

(defn edit
  "edit document specified by path using config as base"
  [config file]
  (def file_path (path/join (config :wiki-dir) file))
  (def parent_dir (path/dirname file_path))
  (if (not (os/stat parent_dir))
    (do (prin "Creating parent directories for " file " ... ")
        (flush)
        (fs/create-directories parent_dir)
        (print "Done.")))
  (if (= (config :editor) :cat)
      (print (slurp file_path))
      (do
        (os/execute [(config :editor) file_path] :p)
        (def change_count (length (get-changes (config :arch-dir))))
        # TODO smarter commit
        (cond
          (= change_count 0) (do (print "No changes, not commiting..."))
          (= change_count 1) (do (git config "add" "-A") (commit config (string "wiki: updated " file)))
          (> change_count 1) (do (git config "add" "-A") (commit config (string "wiki: session from " file))))
        (if (> change_count 0) (if (config :sync)(git/async config "push"))))))

(defn trim-prefix [prefix str]
  (if (string/has-prefix? prefix str)
      (slice str (length prefix) -1)
      str))

(defn trim-suffix [suffix str]
  (if (string/has-suffix? suffix str)
      (slice str 0 (* -1 (+ 1 (length suffix))))
      str))

(defn search
  "search document based on a regex query and select it interactivly using config"
  [config query]
  (def found_files (map |(trim-prefix (string (path/basename (config :wiki-dir)) "/") $0)
                     (filter |(is-doc $0)
                           (string/split "\n" (git config "grep" "-i" "-l" query ":(exclude).obsidian/*" "./*")))))
  (def selected_file (file/select config :files-override found_files))
  (if selected_file
      (edit config selected_file)
      (eprint "No file selected!")))

(defn edit/interactive
  "edit a document selected interactivly based on config"
  [config]
  (def file (file/select config))
  (if file
    (edit config file)
    (eprint "No file selected!")))

(defn log
  "edit log file for date specified by an array of natural date input that can be empty to default to today"
  [config date_arr]
  (def date_str (if (= (length date_arr) 0) "today" (string/join date_arr " ")))
  (def parsed_date (:date-format (date/parse-date date_str)))
  (def doc_path (string "log/" parsed_date ".md"))
  (def doc_abs_path (path/join (config :wiki-dir) doc_path))
  (if (not (os/stat doc_abs_path)) (spit doc_abs_path (get-default-log-doc parsed_date)))
  (edit config doc_path))

(defn sync
  "synchronize wiki specified by config synchroniously"
  [config]
  (os/execute ["git" "-C" (config :arch-dir) "pull"] :p)
  (os/execute ["git" "-C" (config :arch-dir) "push"] :p))

(defn mv
  "move document from source to target path while also changing links linking to it"
  [config source target] # TODO also fix links so they still point at the original targets
  # extract links, split them, url-decode each element, change them according to the planned movement, url encode each element, combine them, read the file into string, replace ](old_url) with ](new_url) in the string, write file to new location, delete old file
  (def source_path (path/join (config :wiki-dir) (string source ".md")))
  (def target_path (path/join (config :wiki-dir) (string target ".md")))
  (def target_parent_dir (path/dirname target_path))
  (if (not (os/stat target_parent_dir))
    (do (prin "Creating parent directories for " target_path " ... ")
        (flush)
        (fs/create-directories target_parent_dir)
        (print "Done.")))
  (git config "mv" source_path target_path)
  (git config "add" source_path)
  (git config "add" target_path)
  (commit config (string "wiki: moved " source " to " target))
  (if (config :sync) (git/async config "push")))

(def patt_md_without_header "PEG-Pattern that captures the content of a markdown file without the metadata header"
  (peg/compile ~(* (opt (* "---\n" (any (* (not "\n---\n") 1)) "\n---\n" (opt "\n"))) (capture (* (any 1))))))

(defn get-content-without-header
  "get content of document without metadata header"
  [path] ((peg/match patt_md_without_header (slurp path)) 0))

(defn get-links
  "get all links from document specified by path"
  [config path]
  (md/get-links (get-content-without-header (path/join (config :wiki-dir) path))))

(defn is-local-link?
  "check wether a given link it a local link or an external one"
  [link] # NOTE very primitive check may need to be improved later
  (if ((uri/parse (link :target)) :scheme) false true))

(defn relative-link-to-id [wiki-dir file-path relative-link-path]
  (setdyn :path-cwd (path/dirname file-path)) # TODO remove this hack that is needed for spork/path/abspath to work correctly
  (trim-prefix wiki-dir (trim-suffix ".md" ((uri/parse (path/abspath relative-link-path)) :path))))

(defn get-graph
  "returns a graph describing the wiki using a adjacency list implemented with a map"
  [config]
  (def adj @{})
  (each file (get-files config)
    (def file-id (trim-suffix ".md" file))
    (put adj file-id @[])
    (let [links (filter (fn [x] (is-local-link? (x :target))) (get-links config file))]
      (each link (map (fn [x] (relative-link-to-id (config :wiki-dir) file (x :target))) links)
        (array/push (adj file-id) link))))
    #(if (= (length (adj file-id)) 0) (put adj file-id nil))) # Hide files that don't link to anything from graph
  adj)

(defn graph/gtk
  "use local graphviz install to render the wiki graph"
  [adj]
  (def streams (os/pipe))
  (ev/write (streams 1) (graph/dot adj))
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (prin "Starting Interface... ") (flush)
  (os/spawn ["dot" "-Tgtk"] :pd {:in (streams 0) :out fout :err ferr})
  (print "Done."))

(defn graph
  "execute a graph subcommand based on config and argument list given"
  [config args]
  (match args
    ["graphical"] (graph/gtk (get-graph config))
    ["dot"] (print (graph/dot (get-graph config)))
    ["json"] (print (graph/json (get-graph config)))
    ["blockdiag"] (print (graph/blockdiag (get-graph config)))
    ["mermaid"] (print (graph/mermaid (get-graph config)))
    [] (graph/gtk (get-graph config))
    _ (do (eprint "Unknown command")
          (os/exit 1))))

(defn check_links
  "check for broken links in document specified by path and config"
  [config file-id]
  (def broken_links @[])
  (def file-path (string file-id ".md"))
  (def links (filter is-local-link? (get-links config file-path))) # TODO ensure that image links are also checked in some way
  (each link links
    (def target (string (path/join (config :wiki-dir) (path/dirname file-id) (link :target)) ".md"))
    (if (not= (os/stat target :mode) :file)
        (array/push broken_links {:target target
                                  :raw-target (link :target)
                                  :name (link :name)})))
  broken_links)

(defn lint
  "lint all files matching optional pattern array in wiki specified by config"
  [config &opt patterns] # TODO patterns are interpreted using globs for strings and as peg-patterns when they are of type :core/peg
  (def pegs
    (map (fn [x] (peg/compile (glob/glob-to-peg x)))
         (if (or (not patterns) (= (length patterns) 0))
             ["*"]
             patterns)))
  (each file (get-files config)
    (def file-id (trim-suffix ".md" file))
    (if (label matches
          (each peg pegs
            (if (peg/match peg file-id) (return matches true)))
          (return matches false))
        (let [result (check_links config file-id)]
             (if (> (length result) 0)
                 (do (eprint "Errors in " file ":")
                     (each err result (print (string/format "%P" err)))
                     (print)))))))

(defn ls_command
  "list all files to stdout starting from path in wiki specified by config"
  [config patterns] # TODO patterns are interpreted using globs for strings and as peg-patterns when they are of type :core/peg
  (def pegs
    (map (fn [x] (peg/compile (glob/glob-to-peg x)))
         (if (or (not patterns) (= (length patterns) 0))
             ["*"]
             patterns)))
  (each file (get-files config)
    (def file-id (trim-suffix ".md" file))
    (if (label matches
          (each peg pegs
            (if (peg/match peg file-id) (return matches true)))
          (return matches false))
        (print file-id))))

(defn- config/load [arch-dir]
  (def conf-path (path/join arch-dir ".glyph" "config.jdn"))
  (try (parse (slurp conf-path))
       ([err] (error "Could not parse glyph config"))))

(defn config/eval [arch-dir eval-func &opt commit-message]
  (def conf-path (path/join arch-dir ".glyph" "config.jdn"))
  (with [lock (flock/acquire conf-path :block :exclusive)]
    (def old-conf (config/load arch-dir))
    (def new-conf (eval-func old-conf))
    (spit conf-path (string/format "%j" new-conf))
    (def git-conf {:arch-dir arch-dir})
    (git/loud git-conf "reset")
    (git/loud git-conf "add" ".glyph/config.jdn")
    (default commit-message "config: updated config")
    (git/loud git-conf "commit" "-m" commit-message)
    (flock/release lock)))

(defn module/add [arch-dir root-conf name path description]
  (def posix-path (path/posix/join ;(path/parts path)))
  (sh/create-dirs (path/join arch-dir ;(path/posix/parts posix-path)))
  (config/eval
    arch-dir
    (fn [x]
      (put-in x [:modules name :path] posix-path)
      (put-in x [:modules name :description] description)
      x)
    (string "config: added new module " name " at " path)))

(defn cli/modules/add [arch-dir root-conf]
  (def res
    (argparse/argparse
      "Add a new module to the glyph archive"
      "name" {:kind :option
              :required true
              :short "n"
              :help "the name of the new module"}
      "path" {:kind :option
              :required true
              :short "p"
              :help "the path of the new module, must be a relative path from the arch_dir root"}
      "description" {:kind :option
                     :required true
                     :short "d"
                     :help "the description of the new module"}))
  (unless res (os/exit 1))
  (module/add arch-dir root-conf (res "name") (res "path") (res "description"))
  (print `module was added to index. You can now add a .main script and manage it via git.
         For examples for .main script check the glyph main repo at https://tasadar.net/tionis/glyph`))

(defn module/ls [arch-dir root-conf &opt glob-pattern]
  (default glob-pattern "*")
  (def pattern (glob/glob-to-peg glob-pattern))
  (def ret @[])
  (eachk k (root-conf :modules)
    (if (peg/match pattern k) (array/push ret k)))
  ret)

(defn cli/modules/ls [arch-dir root-conf]
  (def res
    (argparse/argparse
      "List modules with an optional pattern"
      "output" {:kind :option
                :short "o"
               :help "Output format, valid options are jdn, jsonl, pretty"}
      :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (def pattern (first (res :default)))
  (def modules (module/ls arch-dir root-conf pattern))
  (case (res "output")
    "jdn" (print (string/join (map |(string/format "%j" (get-in root-conf [:modules $0])) modules) "\n"))
    "jsonl" (print (string/join (map |(json/encode (get-in root-conf [:modules $0])) modules) "\n"))
    "pretty" (print (string/join (map |(string/format "%P" (get-in root-conf [:modules $0])) modules) "\n"))
    (print (string/join (map |(string $0 " - " (get-in root-conf [:modules $0 :description])) modules) "\n"))))

(defn module/rm [arch-dir root-conf module-name]
  (config/eval
    arch-dir
    (fn [x] (put-in x [:modules module-name] nil) x)
    (string "config: removed module " module-name)))

(defn cli/modules/rm [arch-dir root-conf]
  (def res
    (argparse/argparse
      "remove a module"
      :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (if (= (length (res :default)) 0) (do (print "Specify module to remove!") (os/exit 1)))
  (module/rm arch-dir root-conf (first (res :default)))
  (print "module removed from index, if the module-data still exists please remove it now."))

(defn cli/modules/help [arch-dir root-conf]
  (print `Available Subcommands:
           add - add a new module
           ls - list modules
           rm - remove a module
           help - show this help`))


(defn cli/alias [arch-dir root-conf]
  (error "not implemented yet") # TODO
  )

(defn cli/wiki [arch-dir root-conf]
  (def res (argparse/argparse
    ```A simple local cli wiki using git for synchronization
       for help with commands use --command_help```
   "wiki_dir" {:kind :option
               :short "wd"
               :help "Manually set wiki_dir"}
   "command_help" {:kind :flag
                   :short "ch"
                   :help "Prints command help"}
   "no_commit" {:kind :flag
                :short "nc"
                :help "Do not commit changes"}
   "no_sync" {:kind :flag
              :short "ns"
              :help "Do not automatically sync repo in background (does not apply to manual sync). This is enabled by default if $WIKI_NO_SYNC is set to \"true\""}
   "force" {:kind :flag
            :short "f"
            :help "foce selected operation, works for rm & mv"}
   "no_pull" {:kind :flag
              :short "np"
              :help "do not pull from repo"}
   "ask-commit-message" {:kind :flag
                         :short "ac"
                         :help "ask for the commit message instead of auto generating one"}
   "cat" {:kind :flag
          :short "c"
          :help "do not edit selected file, just print it to stdout"}
   "verbose" {:kind :flag
              :short "v"
              :action (fn [] (setdyn :verbose true) (print "Verbose Mode enabled!")) # TODO use verbose flag in other funcs
              :help "more verbose logging"}
   :default {:kind :accumulate
             :help positional_args_help_string}))
  (unless res (os/exit 1)) # exit with error if the arguments cannot be parsed
  (if (res "command_help") (do (print_command_help) (os/exit 0)))
  (def args (res :default))
  (def config @{})
  (put config :argparse res)
  (if (or (res "no_sync") (= (os/getenv "WIKI_NO_SYNC") "true"))
    (put config :sync false)
    (put config :sync true))
  (if (res "wiki_dir")
      (do (put config :wiki-dir (res "wiki_dir"))
          (put config :arch-dir (exec-slurp "git" "-C" (config :wiki-dir) "rev-parse" "--show-toplevel")))
      (do (put config :wiki-dir (path/join arch-dir (root-conf :wiki-dir)))
          (put config :arch-dir arch-dir)))
  (let [wiki_dir_stat (os/stat (config :wiki-dir))]
    (if (or (nil? wiki_dir_stat) (not= (wiki_dir_stat :mode) :directory))
        (do (eprint "Wiki dir does not exist or is not a directory!")
            (os/exit 1))))
  (if (res "cat")
      (put config :editor :cat)
      (if (os/getenv "EDITOR")
          (put config :editor (os/getenv "EDITOR"))
          (put config :editor "vim"))) # fallback to default editor
  (if (config :sync)
      (if (and (not (res "no_pull"))
               (not (= args @["sync"]))) # ensure pull is not executed two times for manual sync
          (git/async config "pull")))
  (match args
    ["help"] (print_command_help)
    ["search" & search_terms] (search config (string/join search_terms " "))
    ["ls" & patterns] (ls_command config patterns)
    ["rm" file] (rm config file)
    ["rm"] (rm/interactive config)
    ["mv" source target] (mv config source target)
    ["log" & date_arr] (log config date_arr)
    ["sync"] (sync config)
    ["lint" & patterns] (lint config patterns)
    ["graph" & args] (graph config args)
    [file] (edit config (string file ".md"))
    nil (edit/interactive config)
    _ (print "Invalid syntax!")))

(defn cli/fsck [arch-dir root-conf]
  (os/execute ["git" "-C" arch-dir "fsck"] :p))

(defn cli/modules/execute [arch-dir root-conf name]
  # TODO also look up aliases
  (def config {:arch-dir arch-dir})
  (git/async config "pull")
  (case name # Check if module is a built-in one
    "wiki" (cli/wiki arch-dir root-conf)
    (let [alias (get-in root-conf [:aliases name])
          module-name (if alias (alias :target) name)]
      (if (get-in root-conf [:modules module-name] nil)
          (do (def module-path (path/join arch-dir (get-in root-conf [:modules module-name :path])))
              (def prev-dir (os/cwd))
              (defer (os/cd prev-dir)
               (os/cd module-path)
               (os/execute [".main" ;(slice (dyn :args) 1 -1)]))
               (if (index-of name (map |($0 1) (get-changes module-path)))
                   (do (git config "add" name)
                       (git config "commit" "-m" (string "updated " name))
                       (git config "push"))))
          (do (eprint "module does not exist, use help to list existing ones")
              (os/exit 1))))))

(defn cli/modules [arch-dir root-conf]
  (if (<= (length (dyn :args)) 1)
      (do (cli/modules/ls arch-dir root-conf)
          (os/exit 0)))
  (def subcommand ((dyn :args) 1))
  (setdyn :args [((dyn :args) 0) ;(slice (dyn :args) 2 -1)])
  (case subcommand
    "add" (cli/modules/add arch-dir root-conf)
    "ls" (cli/modules/ls arch-dir root-conf)
    "rm" (cli/modules/rm arch-dir root-conf)
    "help" (cli/modules/help arch-dir root-conf)
    (cli/modules/execute arch-dir root-conf subcommand)))

(def default-root-conf {:wiki-dir "wiki" :modules []})

(defn print-root-help [arch-dir root-conf]
  (def preinstalled `Available Subcommands:
                      modules - manage your custom modules, use 'glyph module --help' for more information
                      alias - manage your aliases
                      git - execute git command on the arch repo
                      sync - sync the glyph archive
                      fsck - perform a filesystem check of arch repo
                      help - print this help`)
  (def custom @"")
  (if (root-conf :modules) (eachk k (root-conf :modules)
                                    (buffer/push custom "  " k " - " (get-in root-conf [:modules k :description]) "\n")))
  (if (root-conf :aliases) (eachk k (root-conf :aliases)
                                    (buffer/push custom "  " k " - alias for" (get-in root-conf [:aliases k :target]) "\n")))
  (if (= (length custom) 0)
    (print preinstalled)
    (do (prin (string preinstalled "\n" custom)) (flush))))

(defn main [&]
  (var root-conf @{})
  # TODO read myself and check if it matches any module or alias, if it does use it as first arg and proceed as normal
  # TODO add command to create symlinks for module or alias
  (def arch-dir (do (def env_arch_dir (os/getenv "GLYPH_ARCH_DIR")) # TODO[branding] change this env var
                    (def env_arch_stat (if env_arch_dir (os/stat env_arch_dir) nil))
                    (if (and env_arch_dir (= (env_arch_stat :mode) :directory))
                        env_arch_dir
                        (get-default-arch-dir))))
  # TODO add default wiki module to root-conf
  (os/cd arch-dir) # TODO[branding] also change the default config.jdn location to remove glyph branding
  (let [root-conf-path (path/join arch-dir ".glyph" "config.jdn") # TODO don't auto write a glyph config add a command for it
        root-conf-stat (os/stat root-conf-path)]
        (if (or (not root-conf-stat) (not= (root-conf-stat :mode) :file))
            (do (set root-conf default-root-conf)
                (let [glyph-path (path/join arch-dir ".glyph")
                      glyph-stat (os/stat glyph-path)]
                     (if (not glyph-stat)
                         (os/mkdir glyph-path)))
                (spit root-conf-path root-conf)
                (def git-conf {:arch-dir arch-dir})
                (git git-conf "reset")
                (git git-conf "add" ".glyph/config.jdn")
                (git git-conf "commit" "-m" "glyph: initialized config"))
            (try (set root-conf (parse (slurp root-conf-path)))
                 ([err] (eprint "Could not load glyph config: " err)
                        (os/exit 1)))))
  # TODO never overwrite user config, not even in-memory
  (put-in root-conf [:modules "wiki"] {:description "default wiki implementation" :path "wiki"}) # TODO add special handler here?
  (let [runtime-name (path/basename (first (dyn :args)))]
    (if ((merge (get root-conf :modules {}) (get root-conf :aliases {}))
         runtime-name)
        (do (array/insert (dyn :args) 0 "glyph")
            (put (dyn :args) 1 runtime-name))))
  (def subcommand (get (dyn :args) 1 nil))
  (array/remove (dyn :args) 1)
  (case subcommand
    # TODO add init command to write out default config
    "modules" (cli/modules arch-dir root-conf)
    "alias" (cli/alias arch-dir root-conf)
    "git" (os/exit (os/execute ["git" "-C" arch-dir ;(slice (dyn :args) 1 -1)] :p))
    "help" (print-root-help arch-dir root-conf)
    "--help" (print-root-help arch-dir root-conf)
    "-h" (print-root-help arch-dir root-conf)
    "" (print-root-help arch-dir root-conf)
    "sync" (sync {:arch-dir arch-dir})
    "fsck" (cli/fsck arch-dir root-conf) # TODO required?
    nil (print-root-help arch-dir root-conf)
    (cli/modules/execute arch-dir root-conf subcommand)))
