#!/bin/env janet
(import ./filesystem)
(import ./date)
(import jff)
(use spork)

# TODO
# preview for file selector still missing

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

(def patt_without_md (peg/compile '{:main (* (capture (any (* (not ".md") 1))) ".md")}))

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
  (let [x (os/spawn cmd :p {:out :pipe :err :pipe})
        s (:read (x :out) :all)]
    (:wait x)
    s))

(defn git [config & args]
  (shell-out ["git" "-C" (config :wiki_dir) ;args]))

(def positional_args_help_string
  (string "Command to run or document to open\n"
          "If no command or file is given it switches to an interactiv document seletor\n"
          "Supported commands:\n"
          "- rm\n"
          "- log\n"
          "- sync\n"
          "- git"))

(defn parse-log-item
  "Parses a log item and outputs a struct describing the time period for task, its completeness status and its description"
  [log-item-string] 
  (def log-item-peg '{:main 0})) # TODO build this peg, it should output the datetime string

(defn print_command_help []
  (print positional_args_help_string))

(defn leap-year?
  ```
  Given a year, returns true if the year is a leap year, false otherwise.
  ```
  [year]
  (let [dy |(= 0 (% year $))]
    (cond
      (dy 400) true
      (dy 100) false
      (dy 4) true
      false)))

(def argparse-params
  [(string "A simple local cli wiki using git for synchronization\n"
           "for help with commands use --command_help")
   "wiki_dir" {:kind :flag
               :help "Manually set wiki_dir"}
   "command_help" {:kind :flag
                   :help "Prints command help"}
   "no_commit" {:kind :flag
                :help "Do not commit changes"}
   "no_pull" {:kind :flag
              :help "do not pull from repo"}
   "ask_commit_message" {:kind :flag
                         :help "ask for the commit message instead of auto generating one"}
   "search_term" {:kind :option
                  :short "s"
                  :help "search for a word or regex"}
   "cat" {:kind :option
          :short "c"
          :help "do not edit selected file, just print it to stdout"}
   "verbose" {:kind :flag
              :short "v"
              :help "more verbose logging"}
   :default {:kind :accumulate
             :help positional_args_help_string}])

(defn date->iso8601 [date_to_transform] (string (date_to_transform :year) "-" (+ (date_to_transform :month) 1) "-" (+ (date_to_transform :month-day) 1)))

(defn parse_date
  "consumes a date in some semi-natural syntax and returns a struct formatted like {:year :month :day :year-day :month-day :week-day}"
  [date_str]
  (cond
    (peg/match ~(* "today" -1) date_str) (date->iso8601 (date/today-local))
    (peg/match ~(* "tomorrow" -1) date_str) (date->iso8601 (date/days-after-local 1))
    (peg/match ~(* "yesterday" -1) date_str) (date->iso8601 (date/days-ago-local 2))
    (error (string "Could not parse date: " date_str))))
  # TODO check if string is already in rfc3339 format and parse it normally
  # TODO check if string is in 
  # TODO
  # - $year-$month-$day
  # - $month-$day
  # - $day
  # - $weekday (this week)
  # - today
  # - tomorrow
  # - yesterday
  # - $x days ago
  # - in $x days
  # - next week
  # - last week
  # - $x weeks ago
  # - in $x weeks
  # - last $week_day
  # - next $week_day
  # - next month
  # - last month
  # - in $x months
  # - $x months ago
  # take inspiration from https://github.com/subsetpark/janet-dtgb and https://git.sr.ht/~pepe/bearimy/

(def ls-files-peg
    "Peg to handle files from git ls-files"
    (peg/compile
      ~{:param (+ (* `"` '(any (if-not `"` (* (? "\\") 1))) `"`)
                  (* `'` '(any (if-not `'` (* (? "\\") 1))) `'`)
                  '(some (if-not "" 1)))
        :main (any (* (capture (any (* (not "\n") 1))) "\n"))}))

(defn get-files [config]
  (map |((peg/match ~(* ,(config :wiki_dir) (capture (any 1))) $0) 0)
       (filter |(peg/match patt_without_md $0)
               (filesystem/list-all-files (config :wiki_dir)))))
  #(peg/match ls-files-peg (string (git config "ls-files")) "\n"))
  # - Use git ls-files as it is faster
  #   warning: ls-files does not print special chars but puts the paths between " and escapes the special chars

(defn interactive-select [arr]
  (jff/choose "" arr))

(defn file/select [config &named files-override preview-command]
  (def files (map |($0 0) (map |(peg/match patt_without_md $0) (if files-override files-override (get-files config)))))
  (def selected (interactive-select files))
  (if selected (string selected ".md") selected))

(defn rm [config file]
  (git config "rm" file)
  (git config "commit" "-m" (string "wiki: deleted " file))
  (git config "push")) # TODO do this async

(defn rm/interactive [config]
  (def file (file/select config))
  (if file
    (rm config file)
    (print "No file selected!")))

(defn edit [config file]
  (if (= (config :editor) :cat)
      (print (slurp file))
      (do
        (print file)
        # TODO edit using $EDITOR
        # if changes
        # git add
        # git commit
        # git push
      )))

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

(defn sync [config]
  (git config "pull")
  (git config "push"))

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
  (if (and (not (res "no_pull"))(not (= args @["sync"]))) (ev/spawn (git config "pull")))
  (match args
    ["help"] (print "Help!")
    ["search" & search_terms] (search config (string/join search_terms " "))
    ["rm" file] (rm config file)
    ["rm"] (rm/interactive config)
    ["log"] (edit config (parse_date "today"))
    ["log" & date_arr] (edit config (parse_date (string/join date_arr " ")))
    ["sync"] (sync config)
    [file] (edit config file)
    nil (edit/interactive config)
    _ (print "Invalid syntax!")))
