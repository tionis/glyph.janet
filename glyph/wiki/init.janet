(import ./markdown :as "md" :export true)
(import ./graph :export true)
(import chronos :as "date")
(import ../git)
#(import fzy :as "fzy")
(import jeff)
(use ../helpers)
(import spork :prefix "")
(import ../options)
(import ../util)
(import ../glob)
(import ../uri)
#(use ./log-item) # disabled due to being unfinished

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
  (string "# " date_str " - " ((date/week-days :long) (today :week-day)) "\n" # TODO maybe add more date metadata here (like week number)
          "[yesterday](" (:date-format (date/days-ago 1 today)) ") <--> [tomorrow](" (:date-format (date/days-after 1 today)) ")\n"
          "\n"
          "## ToDo\n"
          "\n"
          "## Notes\n"
          "\n"
          "## Memos\n"))

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
                  (do (sh/copy-file item (path/join "name" "index.md"))
                      (os/rm item)))))))))

(defn indexify_dirs_recursivly
  "transform dirs recursivly to index.md based md structure starting at path"
  [path]
  (sh/scan-directory path (fn [x]
                                    (if (= ((os/stat x) :mode) :directory)
                                        (indexify_dir x)))))

(defn commit
  "commit staged files, ask user based on config for message, else fallback to default_message"
  [config default_message]
  (if (not (get-in config [:argparse "no-commit"]))
      (if (get-in config [:argparse "ask-commit-message"])
        (do (prin "Commit Message: ")
            (def message (string/trim (file/read stdin :line)))
            (if (= message "")
                (git/loud (config :wiki-dir) "commit" "-m" default_message)
                (git/loud (config :wiki-dir) "commit" "-m" message)))
        (git/loud (config :wiki-dir) "commit" "-m" default_message))))

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
            (filter |(is-doc $0) # TODO migrate away from this simple solution
                    (sh/list-all-files p))))) # TODO migration to the inclusion of file endings and using the get-doc-path function to get a full valid wiki path from an ambigous pathless link
  #(peg/match ls-files-peg (string (git/ ["ls-files"])) "\n")) # TODO implement this as it is probably faster
  # - maybe use git ls-files as it is faster?
  # - warning: ls-files does not print special chars but puts the paths between " and escapes the special chars -> problem with newlines?
  # - problem: this is a bit more complex and I would have to fix my PEG above to correctly parse the output again

(defn interactive-select
  "let user interactivly select an element of the given array"
  [arr]
  (jeff/choose arr :prmpt "" :keywords? true :use-fzf (dyn :use-fzf)))

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
  (git/loud (config :wiki-dir) "rm" (string file ".md"))
  (commit config (string "deleted " file))
  (if (config :sync) (git/push (config :wiki-dir) :background true)))

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
        (sh/create-dirs parent_dir)
        (print "Done.")))
  (if (= (config :editor) :cat)
      (print (slurp file_path))
      (do
        (os/execute [(config :editor) file_path] :p)
        (def change-count (length (git/changes (config :wiki-dir))))
        # TODO smarter commit
        (cond
          (= change-count 0) (do (print "No changes, not commiting..."))
          (= change-count 1) (do (git/loud (config :wiki-dir) "add" "-A") (commit config (string "updated " file)))
          (> change-count 1) (do (git/loud (config :wiki-dir) "add" "-A") (commit config (string "session from " file))))
        (if (> change-count 0) (if (config :sync) (git/push (config :wiki-dir) :background true))))))

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
                           (string/split "\n" (git/exec-slurp (config :wiki-dir) "grep" "-i" "-l" query ":(exclude).obsidian/*" "./*")))))
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
        (sh/create-dirs target_parent_dir)
        (print "Done.")))
  (git/loud (config :wiki-dir) "mv" source_path target_path)
  (git/loud (config :wiki-dir) "add" source_path)
  (git/loud (config :wiki-dir) "add" target_path)
  (commit config (string "moved " source " to " target))
  (if (config :sync) (git/push (config :wiki-dir) :background true)))

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

(defn sync
  "synchronize wiki specified by config synchroniously"
  [config]
  (git/pull (config :wiki-dir))
  (git/push (config :wiki-dir) :ensure-push true))

(def- positional-args-help-string
  `Command to run or document to open
  If no command or file is given it switches to an interactiv document selector
  Supported commands:
    ls $optional_path - list all files at path or root if not path was given
    rm $path - delete document at path
    mv $source $target - move document from $source to $target
    search $search_term - search using a regex
    log $optional_natural_date - edit a log for an optional date
    lint $optional_paths - lint whole wiki or a list of paths
    graph - show a graph of the wiki
    sync - sync the repo
    shell - open a shell session in git repo and auto commit changes
    git $args - pass args thru to git`)

(defn cli [args additional-commands]
  # Parse special subcommands without evaluating normal options
  (def pre-commands (merge additional-commands
                           {"shell" (fn [args] (shell (os/cwd) args))
                            "git" (fn [args] (os/execute ["git" ;args] :p))}))
  (when (and (first args) (pre-commands (first args)))
    ((pre-commands (first args)) (slice args 1 -1))
    (os/exit 0))
  (def res (options/parse
    :args (array/concat @[""] args)
    :description `A simple local cli wiki using git for synchronization
                 for help with commands use --command_help`
    :options {"command_help" {:kind :flag
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
              "fzf" {:kind :flag
                     :action (fn [] (setdyn :use-fzf true))
                     :help "use fzf instead of jeff for interactive selection"}
              "cat" {:kind :flag
                     :short "c"
                     :help "do not edit selected file, just print it to stdout"}
              "verbose" {:kind :flag
                         :short "v"
                         :action (fn [] (setdyn :verbose true) (print "Verbose Mode enabled!")) # TODO use verbose flag in other funcs
                         :help "more verbose logging"}
              :default {:kind :accumulate
                        :help positional-args-help-string}}))
  (unless res (os/exit 1)) # exit with error if the arguments cannot be parsed
  (if (res "command_help") (do (print positional-args-help-string) (os/exit 0)))
  (def args (res :default))
  (def config @{})
  (put config :argparse res)
  (put config :sync (not (or (res "no_sync") (= (os/getenv "WIKI_NO_SYNC") "true"))))
  (if (dyn :wiki-dir)
    (put config :wiki-dir (dyn :wiki-dir))
    (put config :wiki-dir (os/cwd)))
  (let [wiki_dir_stat (os/stat (config :wiki-dir))]
    (if (or (nil? wiki_dir_stat) (not= (wiki_dir_stat :mode) :directory))
        (do (eprint "Wiki dir does not exist or is not a directory!")
            (os/exit 1))))
  (if (res "cat")
      (put config :editor :cat)
      (if (os/getenv "EDITOR")
          (put config :editor (os/getenv "EDITOR"))
          (put config :editor "vim"))) # fallback to default editor
  (if (and (config :sync) (not= (first args) "sync"))
      (if (and (not (res "no_pull"))
               (not (= args @["sync"]))) # ensure pull is not executed two times for manual sync
          (git/pull (config :wiki-dir) :background true)))
  (match args
    ["help"] (print positional-args-help-string)
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

(defn main [myself & args]
  (cli args []))
