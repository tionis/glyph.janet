(import spork/sh)
(import spork/path)
(import ./daemon)

(defn exec-slurp
  "given a config and some arguments execute the git subcommand on wiki"
  [dir & args]
  (sh/exec-slurp "git" "-C" dir ;args))

(defn loud [dir & args] (os/execute ["git" "-C" dir ;args] :p))

(def- status_codes
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

(def- patt_status_line "PEG-Pattern that parsed one line of git status --porcellain=v1 into a tuple of changetype and filename"
  (peg/compile ~(* (opt " ") (capture (between 1 2 (* (not " ") 1))) " " (capture (some 1)))))

(defn changes # TODO migrate to porcelain v2 to detect submodule states https://git-scm.com/docs/git-status#_changed_tracked_entries
  "give a config get the changes in the working tree of the git repo"
  [git-repo-dir]
  (def changes @[])
  (each line (string/split "\n" (exec-slurp git-repo-dir "status" "--porcelain=v1"))
    (if (and line (not= line ""))
      (let [result (peg/match patt_status_line line)]
        (array/push changes [(status_codes (result 0)) (result 1)]))))
  (def ret @{})
  (each change changes
    (put ret (change 1) (change 0)))
  ret)

(def- submodules-status-line-peg "pattern to parse a line from git submodules status for it's submodule path"
  (peg/compile ~(* (+ " " "+" "-") (40 :w) " " (<- (to (+ " " -1))) (? (* " " (to -1))))))

(defn ls-submodule-paths
  "lists submodule paths in the repo at dir, if recursive is true this is done recursivly"
  [dir &named recursive]
  (def lines (string/split "\n" (if recursive
                                  (exec-slurp dir "submodule" "status" "--recursive")
                                  (exec-slurp dir "submodule" "status"))))
  (map |(first (peg/match submodules-status-line-peg $0)) lines))

(defn async
  "given a git dir and some arguments execute the git subcommand on the given repo asynchroniously"
  [dir & args]
  (def fout (sh/devnull))
  (def ferr (sh/devnull))
  (os/spawn ["git" "-C" dir ;args] :pd {:out fout :err ferr}))
  #(daemon/add-job ["git" "-C" dir ;args])) # TODO use glyph background daemon if possible

(defn pull
  "git pull the specified repo with modifiers"
  [dir &named background silent remote]
  (def args @["pull" "--recurse-submodules=on-demand" "--autostash"])
  (if remote (array/push args remote))
  (if background
    (do (async dir ;args))
    (do (if silent
          (exec-slurp dir ;args)
          (loud dir ;args)))))

(defn ls-submodules
  [dir]
  (def gitmodules-path (path/join dir ".gitmodules"))
  (if (not (os/stat gitmodules-path))
    []
    (let [lines (string/split "\n" (exec-slurp dir "config" "--file" gitmodules-path "--name-only" "--get-regexp" "submodule.*.path"))
          patt (peg/compile ~(* "submodule." (capture (any (* (not (* ".path" -1)) 1))) ".path" -1))]
      (map |(first (peg/match patt $0)) lines))))

(defn current-branch
  [dir]
  (def result (exec-slurp dir "rev-parse" "--abbrev-ref" "--symbolic-full-name" "HEAD"))
  (if (= result "HEAD")
    (error "HEAD is detached")
    result))

(defn get-unpushed-changes
  [dir &named fetch]
  (if fetch (loud dir fetch))
  (def branch (current-branch dir))
  (filter |(if (= $0 "") false true) (string/split "\n" (exec-slurp dir "rev-list" "--oneline" (string "^origin/" branch) branch))))

(defn push
  "git push the specified repo with modifiers"
  [dir &named async silent ensure-pushed remote]
  (def args @["push"])
  (if remote (array/push args remote))
  (if ensure-pushed
    (each submodule-path (ls-submodule-paths dir :recursive true)
      (try
        (if (> (length (get-unpushed-changes submodule-path)) 0)
            (push submodule-path :async async :silent silent))
        ([err] (print "Skipping " submodule-path " due to " err)))))
  (if async
    (do (async dir ;args))
    (do (if silent
          (exec-slurp dir ;args)
          (loud dir ;args)))))

(defn fsck [dir &named no-recurse]
  (print "Executing fsck at root")
  (loud dir "fsck")
  (print)
  (each submodule-path (ls-submodule-paths dir :recursive (not no-recurse))
    (def path (path/join dir submodule-path))
    (print "Executing fsck at " submodule-path)
    (loud path "fsck")
    (print)))

(defn exec-slurp-all [dir & args]
  (def proc (os/spawn ["git" "-C" "dir" ;args] :px {:out :pipe :err :pipe}))
  (def out (get proc :out))
  (def err (get proc :out))
  (def out-buf @"")
  (def err-buf @"")
  (ev/gather
    (:read out :all out-buf)
    (:read err :all err-buf) # TODO this doesn't work
    (pp (:wait proc)))
  {:out (string/trimr out-buf) :err (string/trimr err-buf) :code 0})

(defn remote/url/get-owner-repo-string
  [url]
  (first
    (peg/match
      ~(+ (* "git@" (thru ":") (capture (any (* (not ".git") 1))) (opt ".git") -1)
          (* "http" (opt "s") "://" (some (* (not "/") 1)) "/" (capture (some (* (not ".git") 1))) (opt ".git") -1))
      url)))

(defn submodules/update/set
  "set the update method of all submodules to value"
  [dir value &named show-message recursive]
  (each submodule-name (ls-submodules dir)
    (if show-message
      (if value
        (print dir ": submodule." submodule-name ".update set to " value)
        (print dir ": submodule." submodule-name ".update unset")))
    (if value
      (loud dir "config" (string "submodule." submodule-name ".update") value)
      (loud dir "config" "--unset" (string "submodule." submodule-name ".update"))))
  (if recursive
    (let [paths (map |(path/join dir $0) (ls-submodule-paths dir :recursive true))]
      (each path paths
        (submodules/update/set path value :show-message show-message)))))

(defn default-branch
  "get the default branch of optional remote"
  [dir &named remote]
  (default remote "origin")
  (let [remote-head-result (exec-slurp-all dir "rev-parse" "--abbrev-ref" (string remote "/HEAD"))]
    (if (= (remote-head-result :code) 0)
      (peg/match ~(* remote "/" (capture (any 1))) (remote-head-result :out))
      (current-branch dir)))) # default to current branch if remote hash no HEAD
