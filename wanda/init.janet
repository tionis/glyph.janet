#!/bin/env janet
(use spork)
(import uri)
(import ./date)
#(use ./log-item) # disabled due to being unfinished
(import ./dateparser)
(import fzy :as "fzy")
(import jff/ui :as "jff")
(import ./markdown :as "md")
(import ./filesystem :as "fs")

# old hack as workaround https://github.com/janet-lang/janet/issues/995 is solved
# will keep this here for future reference
#(ffi/context)
#(ffi/defbind setpgid :int [pid :int pgid :int])
#(ffi/defbind getpgid :int [pid :int])

(def patt_without_md "PEG-Pattern that strips the .md ending of filenames"
  (peg/compile ~(* (capture (any (* (not ".md") 1))) ".md" -1)))

(def patt_git_status_line "PEG-Pattern that parsed one line of git status --porcellain=v1 into a tuple of changetype and filename"
  (peg/compile ~(* " " (capture 1) " " (capture (some 1)))))

(def patt_yaml_header "PEG-Pattern that captures the content of a yaml header in a markdown file"
  (peg/compile ~(* "---\n" (capture (any (* (not "\n---\n") 1))) "\n---\n")))

(def patt_md_without_yaml "PEG-Pattern that captures the content of a markdown file without the yaml header"
  (peg/compile ~(* (opt (* "---\n" (any (* (not "\n---\n") 1)) "\n---\n" (opt "\n"))) (capture (* (any 1))))))

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

(defn indexify_dir
  "transform given dir to index.md based md structure"
  [path]
  (let [items (os/dir path)]
    (each item items
      (let [name (peg/match patt_without_md item)]
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

(defn shell-out
  "Shell out command and return output"
  [cmd]
  (let [x (os/spawn cmd :p {:out :pipe})
        s (:read (x :out) :all)]
    (:wait x)
    (if s s "")))

(defn git
  "given a config and some arguments execute the git subcommand on wiki"
  [config & args]
  (shell-out ["git" "-C" (config :wiki_dir) ;args]))

(def git_status_codes
  "a map describing the meaning of the git status --porcellain=v1 short codes"
  {"A" :added
   "D" :deleted
   "M" :modified
   "R" :renamed
   "C" :copied
   "I" :ignored
   "?" :untracked
   "T" :typechange
   "X" :unreadable})

(defn get_changes
  "give a config get the changes in the working tree of the git repo"
  [config]
  (def ret @[])
  (each line (slice (string/split "\n" (git config "status" "--porcelain=v1")) 0 -2)
    (let [result (peg/match patt_git_status_line line)]
      (array/push ret [(git_status_codes (result 0)) (result 1)])))
  ret)

# TODO remove dependency to setsid
# maybe use c wrapper and c code as seen here:
# https://man7.org/tlpi/code/online/book/daemons/become_daemon.c.html
# this may be blocked until https://github.com/janet-lang/janet/issues/995 is solved
(defn git/async
  "given a config and some arguments execute the git subcommand on wiki asynchroniously"
  [config & args]
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (os/execute ["setsid" "-f" "git" "-C" (config :wiki_dir ) ;args] :p {:out fout :err ferr}))

(defn commit
  "commit staged files, ask user based on config for message, else fallback to default_message"
  [config default_message]
  (if (not (get-in config [:argparse "no-commit"]))
      (if (get-in config [:argparse "ask-commit-message"])
        (do (prin "Commit Message: ")
            (git config "commit" "-m" (file/read stdin :line)))
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

(def argparse-params
  [(string "A simple local cli wiki using git for synchronization\n"
           "for help with commands use --command_help")
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
              :help "more verbose logging"}
   :default {:kind :accumulate
             :help positional_args_help_string}])

(def ls-files-peg
  "Peg to handle files from git ls-files"
  (peg/compile
    ~{:param (+ (* `"` '(any (if-not `"` (* (? "\\") 1))) `"`)
                (* `'` '(any (if-not `'` (* (? "\\") 1))) `'`)
                '(some (if-not "" 1)))
      :main (any (* (capture (any (* (not "\n") 1))) "\n"))}))

(defn get-files
  "given a config and optional path to begin list all documents in wiki (not assets, only documents)"
  [config &opt path]
  (default path "")
  (def p (path/join (config :wiki_dir) path))
  (if (= ((os/stat p) :mode) :file)
      p
      (map |((peg/match ~(* ,p (? (+ "/" "\\")) (capture (any 1))) $0) 0)
            (filter |(peg/match patt_without_md $0)
                    (fs/list-all-files p)))))
  #(peg/match ls-files-peg (string (git config "ls-files")) "\n"))
  # - maybe use git ls-files as it is faster?
  # - warning: ls-files does not print special chars but puts the paths between " and escapes the special chars
  # - problem: this is a bit more complex and I would have to fix my PEG above to correctly parse the output again

(defn interactive-select
  "let user interactivly select an element of the given array"
  [arr]
  (jff/choose "" arr))

(defn file/select
  "let user interactivly select a file, optionally accepts a files-override for a custom file set and preview-command to show the output of in a side window for the currently selected file"
  [config &named files-override preview-command]
  (def files (map |($0 0) (map |(peg/match patt_without_md $0) (if files-override files-override (get-files config)))))
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
  (def file_path (path/join (config :wiki_dir) file))
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
        (def change_count (length (get_changes config)))
        # TODO smarter commit
        (cond
          (= change_count 0) (do (print "No changes, not commiting..."))
          (= change_count 1) (do (git config "add" "-A") (commit config (string "wiki: updated " file)))
          (> change_count 1) (do (git config "add" "-A") (commit config (string "wiki: session from " file))))
        (if (> change_count 0) (if (config :sync)(git/async config "push"))))))

(defn search
  "search document based on a regex query and select it interactivly using config"
  [config query]
  (def found_files (filter |(peg/match patt_without_md $0)
                           (string/split "\n" (string/trim (git config "grep" "-i" "-l" query ":(exclude).obsidian/*" "./*")))))
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
  (def parsed_date (dateparser/parse-date date_str))
  (def doc_path (string "log/" parsed_date ".md"))
  (def doc_abs_path (path/join (config :wiki_dir) doc_path))
  (if (not (os/stat doc_abs_path)) (spit doc_abs_path (get-default-log-doc parsed_date)))
  (edit config doc_path))

(defn sync
  "synchronize wiki specified by config synchroniously"
  [config]
  (os/execute ["git" "-C" (config :wiki_dir) "pull"] :p)
  (os/execute ["git" "-C" (config :wiki_dir) "push"] :p))

(defn mv
  "move document from source to target path while also changing links linking to it"
  [config source target] # TODO also fix links so they still point at the original targets
  # extract links, split them, url-decode each element, change them according to the planned movement, url encode each element, combine them, read the file into string, replace ](old_url) with ](new_url) in the string, write file to new location, delete old file
  (def source_path (path/join (config :wiki_dir) (string source ".md")))
  (def target_path (path/join (config :wiki_dir) (string target ".md")))
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

(defn get-content-without-header
  "get content of document without yaml header"
  [path] ((peg/match patt_md_without_yaml (slurp path)) 0))

(defn get-links
  "get all links from document specified by path"
  [config path]
  (md/get-links (get-content-without-header (path/join (config :wiki_dir) path))))

(defn graph/json
  "get json encoding of graph"
  [adj]
  (json/encode adj))

(defn graph/dot 
  "get dot encoding of graph"
  [adj]
  (var ret @"digraph wiki {\n")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "  \"" k "\"\n")
      (buffer/push ret "  \"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  (buffer/push ret "}"))

(defn graph/blockdiag
  "get blockdiag encoding of graph"
  [adj]
  (var ret @"")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "\"" k "\"\n")
      (buffer/push ret "\"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  ret)

(defn graph/mermaid
  "get mermaid encoding of graph"
  [adj]
  (var ret @"graph TD\n")
  (def id @{})
  (var num 0)
  (eachk k adj
    (put id k num)
    (+= num 1))
  (eachk k adj
    (if (= (length (adj k)) 0)
        (buffer/push ret "  " (id k) "[" k "]\n"))
    (each l (adj k)
      (buffer/push ret "  " (id k) "[" k "] --> " (id l) "\n")))
  ret)

(defn is-local-link?
  "check wether a given link it a local link or an external one"
  [link] # NOTE very primitive check may need to be improved later
  (if ((uri/parse link) :scheme) false true))

(defn get-graph
  "returns a graph describing the wiki using a adjacency list implemented with a map"
  [config]
  (def adj @{})
  (each file (get-files config)
    (put adj file @[])
    (let [links (filter is-local-link? (get-links config file))]
      (each link links
        (array/push (adj file) (link :target)))))
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
  (os/execute ["setsid" "-f" "dot" "-Tgtk"] :p {:in (streams 0) :out fout :err ferr})
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
    [] (graph/gtk config)
    _ (do (eprint "Unknown command")
          (os/exit 1))))

(defn check_links
  "check for broken links in docuement specified by path and config"
  [config path]
  # TODO implement this
  (def broken_links @[])
  (def links (filter is-local-link? (get-links config path))) # TODO ensure that image links are also checked in some way
  (each link links
    (if (not= ((os/stat (string (path/join path (link :target))))) :mode) :file)
        (array/push broken_links link))
  broken_links)

(defn check_all_links
  "check for broken links in whole wiki specified by config"
  [config]
  (each file (get-files config)
    (let [result (check_links config file)]
         (if (> (length result) 0)
             (do (eprint "Error in " file "")
                 (prin) (pp result))))))

(defn lint
  "lint whole wiki specified by config"
  [config paths]
  (if (> (length paths) 0)
      (each path paths
         (check_links config path))
      (check_all_links config)))

(defn ls_command
  "list all files to stdout starting from path in wiki specified by config"
  [config path]
  (each file (get-files config (if (> (length path) 0) (string/join path " ") nil))
    (print ((peg/match patt_without_md file) 0))))

(defn main [_ & raw_args]
  (if (and (> (length raw_args) 0) (= (raw_args 0) "git")) # pass through calls to wiki git without parsing them for flags
      (os/exit (os/execute ["git" "-C" (os/getenv "WIKI_DIR") ;(slice raw_args 1 -1)] :p)))
  (def res (argparse/argparse ;argparse-params))
  (unless res (os/exit 1)) # exit with error if the arguments cannot be parsed
  (if (res "command_help") (do (print_command_help) (os/exit 0)))
  (def args (res :default))
  (def config @{})
  (put config :argparse res)
  (if (or (res "no_sync") (= (os/getenv "WIKI_NO_SYNC") "true"))
    (put config :sync false)
    (put config :sync true))
  (if (res "wiki_dir")
      (put config :wiki_dir (res "wiki_dir"))
      (if (os/getenv "WIKI_DIR")
          (put config :wiki_dir (os/getenv "WIKI_DIR"))
          (put config :wiki_dir (path/join (os/getenv "HOME") "wiki")))) # fallback to default directory
  (let [wiki_dir_stat (os/stat (config :wiki_dir))]
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
    ["ls" & path] (ls_command config path)
    ["rm" file] (rm config file)
    ["rm"] (rm/interactive config)
    ["mv" source target] (mv config source target)
    ["log" & date_arr] (log config date_arr)
    ["sync"] (sync config)
    ["lint" & paths] (lint config paths)
    ["graph" & args] (graph config args)
    [file] (edit config (string file ".md"))
    nil (edit/interactive config)
    _ (print "Invalid syntax!")))
