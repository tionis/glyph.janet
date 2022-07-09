#!/bin/env janet
(import ./filesystem)
(import ./date)
(import ./dateparser)
(import jff/ui :prefix "jff/")
#(use ./log-item) disabled due to being unfinished
(use spork)

# TODO
# - add preview for file selector
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

# old hack as workaround https://github.com/janet-lang/janet/issues/995 is solved
# will keep this here for future reference
#(ffi/context)
#(ffi/defbind setpgid :int [pid :int pgid :int])
#(ffi/defbind getpgid :int [pid :int])

(def patt_without_md (peg/compile '{:main (* (capture (any (* (not ".md") 1))) ".md" -1)}))

(def patt_git_status_line (peg/compile ~(* " " (capture 1) " " (capture (some 1)))))

(def patt_log_item (peg/compile ~(* (any (+ "\t" " "))
                                    "- [ ] "
                                    (capture (any (* (not " | ") 1)))
                                    (opt (* " | " (capture (any 1)))))))

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
          - sync - sync the repo
          - git $args - pass args thru to git`))
(defn print_command_help [] (print positional_args_help_string))

(def argparse-params
  [(string "A simple local cli wiki using git for synchronization\n"
           "for help with commands use --command_help")
   "wiki_dir" {:kind :option
               :help "Manually set wiki_dir"}
   "command_help" {:kind :flag
                   :help "Prints command help"}
   "no_commit" {:kind :flag
                :help "Do not commit changes"}
   "no_pull" {:kind :flag
              :help "do not pull from repo"}
   "ask-commit-message" {:kind :flag
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
  (git/async config "push"))

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
        (if (> change_count 0) (git/async config "push")))))

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

(defn mv [config source target]
  (def source_path (path/join (config :wiki_dir) (string source ".md")))
  (def target_path (path/join (config :wiki_dir) (string target ".md")))
  (pp source_path)
  (git config "mv" source_path target_path)
  (git config "add" source_path)
  (git config "add" target_path)
  (commit config (string "wiki: moved " source " to " target))
  (git/async config "push"))

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
  (if (res "wiki_dir")
      (put config :wiki_dir (res "wiki_dir"))
      (if (os/getenv "WIKI_DIR")
          (put config :wiki_dir (os/getenv "WIKI_DIR"))
          (put config :wiki_dir (path/join (os/getenv "HOME") "wiki")))) # fallback to default directory
  (if (res "cat")
      (put config :editor :cat)
      (if (os/getenv "EDITOR")
          (put config :editor (os/getenv "EDITOR"))
          (put config :editor "vim"))) # fallback to default editor
  (if (and (not (res "no_pull"))
           (not (= args @["sync"])))
      (git/async config "pull"))
  (match args
    ["help"] (print_command_help)
    ["search" & search_terms] (search config (string/join search_terms " "))
    ["ls" & path] (ls_command config path)
    ["rm" file] (rm config file)
    ["rm"] (rm/interactive config)
    ["mv" source target] (mv config source target)
    ["log" & date_arr] (log config date_arr)
    ["sync"] (sync config)
    [file] (edit config (string file ".md"))
    nil (edit/interactive config)
    _ (print "Invalid syntax!")))
