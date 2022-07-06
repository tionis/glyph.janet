#!/bin/env janet
(import ./filesystem)
(import ./date)
(import jff/ui :prefix "jff/")
(use spork)

# TODO
# - add preview for file selector
# - add forking async pull/push
# - finish date parser
# - add log item parser (not sure for what exactly but may be fun to implement and get more familiar with PEGs)
# - add daemon that autocommits on change and pulls regularily to support non-cli workflows/editors
# - think about using file locking to prevent conflicts
# - fix error in date library that jumps from 2022-07-02 -> yesterday -> 2022-06-30
# - prefill new log documents
# - save which doc is currently being edited in cache or use file locks and only commit files not locked by other wiki processes
# - add cal/calendar subcommand which provides an UI for choosing a day for log

# Note for parsing git status porcellain:
# ADDED:     = 'A'
# DELETED    = 'D'
# MODIFIED   = 'M'
# RENAMED    = 'R'
# COPIED     = 'C'
# IGNORED    = 'I'
# UNTRACKED  = '?'
# TYPECHANGE = 'T'
# UNREADABLE = 'X'

# Notes
# Log Item Syntax():
# - [ ] optional_time | description
# time syntax:
# 13:00 = at 13:00
# <13:00 = before 13:00
# >13:00 = after 13:00
# 12:00-13:00 = from 12:00 to 13:00
# 12:00<t<13:00 = somewhen between 12:00 and 13:00
# 12:00<<13:00 = somewhen between 12:00 and 13:00
# each time can be followed by a space and a duration like so:
# 13:00 P2h15m = start at 13:00 and do task for 2h and 15 min
# 12:00<<13:00 P20m = task starts somewhere between 12:00 and 13:00 and needs 20 minutes

# old hack as workaround https://github.com/janet-lang/janet/issues/995 is solved
# will keep this here for future reference
#(ffi/context)
#(ffi/defbind setpgid :int [pid :int pgid :int])
#(ffi/defbind getpgid :int [pid :int])

(def patt_without_md (peg/compile '{:main (* (capture (any (* (not ".md") 1))) ".md")}))

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
  (string "# " date_str #" - " ((date/week-days :long) (today :week-day)) "\n"
          #"[yesterday](" (:format (date/days-ago 1 today)) ") <--> [tomorrow](" (:format (date/days-after 1 today)) ")\n"
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

(defn to_two_digit_string [num]
  (if (< num 9)
    (string "0" num)
    (string num)))

(defn shell-out
  "Shell out command and return output"
  [cmd]
  (let [x (os/spawn cmd :p {:out :pipe :err :pipe})
        s (:read (x :out) :all)]
    (:wait x)
    (if s s "")))

(defn git [config & args] (shell-out ["git" "-C" (config :wiki_dir) ;args]))

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

(defn parse-log-item
  "Parses a log item and outputs a struct describing the time period for task, its completeness status and its description"
  [log-item-string]
  (def log-item-peg '{:main 0})) # TODO build this peg, it should output the datetime string
  #TODO parse datetime string into following struct: {:from date_here :to date_here :duration duration_here_only_if_needed)}
  #date_here can be :beginning_of_time :end_of_time a date struct formatted like (os/date)

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

(defn date->iso8601 [date_to_transform] (string (date_to_transform :year)
                                                "-"
                                                (to_two_digit_string (+ (date_to_transform :month) 1))
                                                "-" 
                                                (to_two_digit_string (+ (date_to_transform :month-day) 1))))

(defn parse_date
  "consumes a date in some semi-natural syntax and returns a struct formatted like {:year :month :day :year-day :month-day :week-day}"
  [date_str]
  (cond
    (peg/match ~(* "today" -1) date_str) (date->iso8601 (date/today-local))
    (peg/match ~(* "tomorrow" -1) date_str) (date->iso8601 (date/days-after-local 1))
    (peg/match ~(* "yesterday" -1) date_str) (date->iso8601 (date/days-ago-local 1))
    (peg/match ~(* (repeat 4 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) date_str
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string "20" date_str)
    (peg/match ~(* (repeat 2 :d) "-" (repeat 2 :d) -1) date_str) (string ((date/today-local) :year) "-" date_str)
    (peg/match ~(* (between 1 2 :d) -1) date_str)
      (let [today (date/today-local)]
           (string (today :year) "-" (to_two_digit_string (+ (today :month) 1)) "-" date_str))
    (peg/match ~(* (some :d) " day" (opt "s") " ago") date_str)
      (let [days_ago (scan-number ((peg/match ~(* (capture (some :d)) " day" (opt "s") " ago") date_str) 0))]
           (date->iso8601 (date/days-ago-local days_ago)))
    (peg/match ~(* "in " (some :d) " day" (opt "s")) date_str)
      (let [days_after (scan-number ((peg/match ~(* "in " (capture (some :d)) " day" (opt "s")) date_str) 0))]
           (date->iso8601 (date/days-after-local days_after)))
    (peg/match ~(* "next week" -1) date_str) (date->iso8601 (date/days-after-local 7))
    (peg/match ~(* "last week" -1) date_str) (date->iso8601 (date/days-ago-local 7))
    # TODO
    # - $weekday (this week)
    # - $x weeks ago
    # - in $x weeks
    # - last $week_day
    # - next $week_day
    # - next month
    # - last month
    # - in $x months
    # - $x months ago
    (error (string "Could not parse date: " date_str))))

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
  (git config "rm" file)
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
  (def parsed_date (parse_date date_str))
  (def doc_path (string "log/" parsed_date ".md"))
  (def doc_abs_path (path/join (config :wiki_dir) doc_path))
  (if (not (os/stat doc_abs_path)) (spit doc_abs_path (get-default-log-doc parsed_date)))
  (edit config doc_path))

(defn sync [config]
  (git config "pull")
  (git config "push"))

(defn mv [config source target]
  (def source_path (path/join (config :wiki_dir) (string source ".md")))
  (def target_path (path/join (config :wiki_dir) (string target ".md")))
  (pp source_path)
  (git config "mv" source_path target_path)
  (git config "add" source_path)
  (git config "add" target_path)
  (commit config (string "wiki: moved " source " to " target))
  (git/async config "push"))

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
    ["ls" & path] (each file (get-files config (if (> (length path) 0) (string/join path " ") nil)) (print file))
    ["rm" file] (rm config file)
    ["rm"] (rm/interactive config)
    ["mv" source target] (mv config source target)
    ["log" & date_arr] (log config date_arr)
    ["sync"] (sync config)
    [file] (edit config (string file ".md"))
    nil (edit/interactive config)
    _ (print "Invalid syntax!")))
