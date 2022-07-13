#!/bin/env janet
(import ./filesystem)
(import ./date)
(import ./dateparser)
(import jff/ui :prefix "jff/")
#(import yaml) # TODO write yaml library
(import ./markdown :as "md")
#(use ./log-item) disabled due to being unfinished
(use spork)

# TODO
# - add preview for file selector -> requires changes in jff
# - finish date parser
# - add log item parser (not sure for what exactly but may be fun to implement and get more familiar with PEGs)
# - add daemon that autocommits on change and pulls regularily to support non-cli workflows/editors
# - think about using file locking to prevent conflicts
# - save which doc is currently being edited in cache or use file locks and only commit files not locked by other wiki processes
# - add cal/calendar subcommand which provides an UI for choosing a day for log
# - add lint subcommand that check for broken links etc across the wiki
# - add server side subtree based wiki sharing
# - think about possibility of integrating hyperlist for recipes, todos and the like
# - add todo parser to show due tasks, show tasks by tag etc.
# - take inspiration of wiki.fish script and allow fuzzy searching of all lines or implement a full text search -> needs jff preview
# - think about adding contacts managment
# - add a nestable key value store using json files as backend to store arbitraty data (could for example be used to track progress in current books etc.)
# - add wiki fixer that fixes common markdown linking mistakes done by e.g. obsidian
#   - fix .md suffix in links -> after editing go over file and ensure all local links are valid and refer to full file name with the .md suffix
# - add indexifier to transform from foo.md to foo/index.md (use mv method to also correct links (check them afterwards?)) (this may fail as index.md need special handling)
# - when moving files also correct links
# - use shlex grammar as inspiration for path/split peg grammar (this is needed for the new file move command implementation)

# peg inspiration:
# https://github.com/sogaiu/janet-peg-samples/blob/master/samples/andrewchambers/janet-shlex.janet
# (def- grammar
#    ~{
#      :ws (set " \t\r\n")
#      :escape (* "\\" (capture 1))
#      :dq-string (accumulate (* "\""
#                                (any (+ :escape (if-not "\"" (capture 1))))
#                                "\""))
#      :sq-string (accumulate (* "'" (any (if-not "'" (capture 1))) "'"))
#      :token-char (+ :escape (* (not :ws) (capture 1)))
#      :token (accumulate (some :token-char))
#      :value (* (any (+ :ws)) (+ :dq-string :sq-string :token) (any :ws))
#      :main (any :value)
#      })

# old hack as workaround https://github.com/janet-lang/janet/issues/995 is solved
# will keep this here for future reference
#(ffi/context)
#(ffi/defbind setpgid :int [pid :int pgid :int])
#(ffi/defbind getpgid :int [pid :int])

(def patt_without_md (peg/compile ~(* (capture (any (* (not ".md") 1))) ".md" -1)))

(def patt_git_status_line (peg/compile ~(* " " (capture 1) " " (capture (some 1)))))

(def patt_yaml_header (peg/compile ~(* "---\n" (capture (any (* (not "\n---\n") 1))) "\n---\n")))

(def patt_md_without_yaml (peg/compile ~(* (opt (* "---\n" (any (* (not "\n---\n") 1)) "\n---\n")) (capture (* (any 1))))))

(def patt_log_item (peg/compile ~(* (any (+ "\t" " "))
                                    "- [ ] "
                                    (capture (any (* (not " | ") 1)))
                                    (opt (* " | " (capture (any 1)))))))

(defn dprint [x]
  (printf "%M" x))

(defn get-null-file []
  (case (os/which)
    :windows "NUL"
    :macos "/dev/null"
    :web (error "Unsupported Operation")
    :linux "/dev/null"
    :freebsd "/dev/null"
    :openbsd "/dev/null"
    :posix "/dev/null"))

(defn get-default-log-doc [date_str]
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
                  (do (filesystem/copy-file item (path/join "name" "index.md"))
                      (os/rm item)))))))))

(defn indexify_dirs_recursivly
  "transform dirs recursivly to index.md based md structure starting at path"
  [path]
  (filesystem/scan-directory path (fn [x]
                                    (if (= ((os/stat x) :mode) :directory)
                                        (indexify_dir x)))))

(defn shell-out
  "Shell out command and return output"
  [cmd]
  (let [x (os/spawn cmd :p {:out :pipe})
        s (:read (x :out) :all)]
    (:wait x)
    (if s s "")))

(defn git [config & args] (shell-out ["git" "-C" (config :wiki_dir) ;args]))

(defn git_status_parse_code [status_code]
  (case status_code
    "A" :added
    "D" :deleted
    "M" :modified
    "R" :renamed
    "C" :copied
    "I" :ignored
    "?" :untracked
    "T" :typechange
    "X" :unreadable
    (error "Unknown git status code")))

(defn get_changes [config]
  (def ret @[])
  (each line (slice (string/split "\n" (git config "status" "--porcelain=v1")) 0 -2)
    (let [result (peg/match patt_git_status_line line)]
      (array/push ret [(git_status_parse_code (result 0)) (result 1)])))
  ret)

# TODO remove dependency to setsid
# maybe use c wrapper and c code as seen here:
# https://man7.org/tlpi/code/online/book/daemons/become_daemon.c.html
# this may be blocked until https://github.com/janet-lang/janet/issues/995 is solved
(defn git/async [config & args]
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (os/execute ["setsid" "-f" "git" "-C" (config :wiki_dir ) ;args] :p {:out fout :err ferr}))

(defn commit [config default_message]
  (if (not (config "no-commit"))
      (if (config "ask-commit-message")
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
(defn print_command_help [] (print positional_args_help_string))

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

(defn get-files [config &opt path]
  (default path "")
  (def p (path/join (config :wiki_dir) path))
  (if (= ((os/stat p) :mode) :file)
      p
      (map |((peg/match ~(* ,p (? (+ "/" "\\")) (capture (any 1))) $0) 0)
            (filter |(peg/match patt_without_md $0)
                    (filesystem/list-all-files p)))))
  #(peg/match ls-files-peg (string (git config "ls-files")) "\n"))
  # - maybe use git ls-files as it is faster?
  # - warning: ls-files does not print special chars but puts the paths between " and escapes the special chars
  # - problem: this is a bit more complex and I would have to fix my PEG above to correctly parse the output again

(defn interactive-select [arr]
  (jff/choose "" arr))

(defn file/select [config &named files-override preview-command]
  (def files (map |($0 0) (map |(peg/match patt_without_md $0) (if files-override files-override (get-files config)))))
  (def selected (interactive-select files))
  (if selected (string selected ".md") selected))

(defn rm [config file]
  (git config "rm" (string file ".md"))
  (commit config (string "wiki: deleted " file))
  (if (config :sync) (git/async config "push")))

(defn rm/interactive [config]
  (def file (file/select config))
  (if file
    (rm config file)
    (print "No file selected!")))

(defn edit [config file]
  (def file_path (path/join (config :wiki_dir) file))
  (def parent_dir (path/dirname file_path))
  (if (not (os/stat parent_dir))
    (do (prin "Creating parent directories for " file " ... ")
        (flush)
        (filesystem/create-directories parent_dir)
        (print "Done.")))
  (if (= (config :editor) :cat)
      (print (slurp file_path))
      (do
        (os/execute [(config :editor) file_path] :p)
        (def change_count (length (string/split "\n" (string/trim (git config "status" "--porcelain=v1")))))
        # TODO smarter commit
        (cond
          (= change_count 0) (do (print "No changes, not commiting..."))
          (= change_count 1) (do (git config "add" "-A") (commit config (string "wiki: updated " file)))
          (> change_count 1) (do (git config "add" "-A") (commit config (string "wiki: session from " file))))
        (if (> change_count 0) (if (config :sync)(git/async config "push"))))))

(defn search [config query]
  (def found_files (filter |(peg/match patt_without_md $0)
                           (string/split "\n" (string/trim (git config "grep" "-i" "-l" query ":(exclude).obsidian/*" "./*")))))
  (def selected_file (file/select config :files-override found_files))
  (if selected_file
      (edit config selected_file)
      (eprint "No file selected!")))

(defn edit/interactive [config]
  (def file (file/select config))
  (if file
    (edit config file)
    (eprint "No file selected!")))

(defn log [config date_arr]
  (def date_str (if (= (length date_arr) 0) "today" (string/join date_arr " ")))
  (def parsed_date (dateparser/parse-date date_str))
  (def doc_path (string "log/" parsed_date ".md"))
  (def doc_abs_path (path/join (config :wiki_dir) doc_path))
  (if (not (os/stat doc_abs_path)) (spit doc_abs_path (get-default-log-doc parsed_date)))
  (edit config doc_path))

(defn sync [config]
  (os/execute ["git" "-C" (config :wiki_dir) "pull"] :p)
  (os/execute ["git" "-C" (config :wiki_dir) "push"] :p))

(defn mv [config source target] # TODO also fix links so they still point at the original targets
  # extract links, split them, url-decode each element, change them according to the planned movement, url encode each element, combine them, read the file into string, replace ](old_url) with ](new_url) in the string, write file to new location, delete old file
  (def source_path (path/join (config :wiki_dir) (string source ".md")))
  (def target_path (path/join (config :wiki_dir) (string target ".md")))
  (def target_parent_dir (path/dirname target_path))
  (if (not (os/stat target_parent_dir))
    (do (prin "Creating parent directories for " target_path " ... ")
        (flush)
        (filesystem/create-directories target_parent_dir)
        (print "Done.")))
  (git config "mv" source_path target_path)
  (git config "add" source_path)
  (git config "add" target_path)
  (commit config (string "wiki: moved " source " to " target))
  (if (config :sync) (git/async config "push")))

(defn get-content-without-header [path] ((peg/match patt_md_without_yaml (slurp path)) 0))

(defn get-links [config path]
  (md/get-links (get-content-without-header (path/join (config :wiki_dir) path))))

(defn dot/encode [adj]
  (var ret @"digraph wiki {\n")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "  \"" k "\"\n")
      (buffer/push ret "  \"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  (buffer/push ret "}"))

(defn blockdiag/encode [adj]
  (var ret @"")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "\"" k "\"\n")
      (buffer/push ret "\"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  ret)

(defn mermaid/encode [adj]
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

(defn is-local-link? [link]
  true
  # TODO return true if link is a local link and not web link or absolute link
  )

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

(defn graph-gtk
  "use local graphviz install to render the wiki graph"
  [config]
  (def streams (os/pipe))
  (ev/write (streams 1) (dot/encode (get-graph config)))
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (prin "Starting Interface... ") (flush)
  (os/execute ["setsid" "-f" "dot" "-Tgtk"] :p {:in (streams 0) :out fout :err ferr})
  (print "Done."))

(defn graph [config args]
  (match args
    ["graphical"] (graph-gtk config)
    ["dot"] (print (dot/encode (get-graph config)))
    ["blockdiag"] (print (blockdiag/encode (get-graph config)))
    ["mermaid"] (print (mermaid/encode (get-graph config)))
    [] (graph-gtk config)
    _ (do (eprint "Unknown command")
          (os/exit 1))))

(defn check_links [config path]
  # TODO implement this
  (def broken_links @[])
  (def links (filter is-local-link? (get-links config path))) # TODO ensure that image links are also checked in some way
  (each link links
    (if (not= ((os/stat (string (path/join path (link :target))))) :mode) :file)
        (array/push broken_links link))
  broken_links)

(defn check_all_links [config]
  (each file (get-files config)
    (let [result (check_links config file)]
         (if (> (length result) 0)
             (do (eprint "Error in " file "")
                 (prin) (pp result))))))

(defn lint [config paths]
  (check_all_links config))

(defn ls_command [config path]
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
  (if (or (res "no_sync") (= (os/getenv "WIKI_NO_SYNC") "true"))
    (put config :sync false)
    (put config :sync true))
  (if (res "wiki_dir")
      (put config :wiki_dir (res "wiki_dir"))
      (if (os/getenv "WIKI_DIR")
          (put config :wiki_dir (os/getenv "WIKI_DIR"))
          (put config :wiki_dir (path/join (os/getenv "HOME") "wiki")))) # fallback to default directory
  (if (not= ((os/stat (config :wiki_dir)) :mode) :directory)
    (do (eprint "Wiki dir does not exist or is not a directory!")
        (os/exit 1)))
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
