(import spork/sh)
(import spork/path)
(import toolbox/jeff)

(defn- exec [& argv]
  (when (not= (os/execute [;argv] :p) 0)
    (error (string "command '" (string/join argv " ") "' failed"))))

(defn exec-slurp
  "given a git dir and some arguments execute the git subcommand on wiki"
  [dir & args]
  (sh/exec-slurp "git" "-C" dir ;args))

(defn loud [dir & args] (os/execute ["git" "-C" dir ;args] :p))

(defn get-top-level [dir]
  (exec-slurp dir "rev-parse" "--show-toplevel"))

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
  "given a git dir get the changes in the working tree of the git repo" # TODO bug does not detect paths with spaces in it due to quoting issue (does not understand quotes)
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

(defn ls-submodule-paths
  "lists submodule paths in the repo at dir, if recursive is true this is done recursivly"
  [dir &named recursive]
  (string/split
    "\n"
    (if recursive
      (exec-slurp dir "submodule" "foreach" "--recursive" "-q" "echo $sm_path")
      (exec-slurp dir "submodule" "foreach" "-q" "echo $sm_path"))))

(defn get-object-path
  [dir object-id &named tree]
  (default tree "HEAD")
  (def lines (filter (fn [x] (not= "" x)) (string/split "\0" (exec-slurp dir "ls-tree" "-z" "-r" tree))))
  (def objects (map |(peg/match ~(* (capture (6 :d)) " " (capture (to " ")) " " (capture (to "\t")) "\t" (capture (to -1)))
                              $0) lines))
  (first (map |($0 3) (filter |(= ($0 2) object-id) objects))))

(defn async
  "given a git dir and some arguments execute the git subcommand on the given repo asynchroniously"
  [dir & args]
  (def fout (sh/devnull))
  (def ferr (sh/devnull))
  (os/spawn ["git" "-C" dir ;args] :pd {:out fout :err ferr}))

(defn pull
  "git pull the specified repo with modifiers"
  [dir &named background silent remote]
  (def args @["pull" "--recurse-submodules=on-demand" "--autostash"])
  # TODO if pull has merge conflict try resolving merge automatically using
  # git mergetool --tool=default
  (if remote (array/push args remote))
  (if background
    (do (async dir ;args))
    (do (if silent
          (exec-slurp dir ;args)
          (loud dir ;args)))))

(defn ls-submodules
  "list submodule names"
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
  (if (os/stat (path/join dir ".git"))
    (do (if fetch (loud dir fetch))
        (def branch (current-branch dir))
        (freeze (filter (fn [x] (if x x (if (= x "") nil x))) (string/trimr (exec-slurp dir "cherry"))))) # TODO parse output or switch to equivalent porcelain command
    []))

(defn push
  "git push the specified repo with modifiers"
  [dir &named silent ensure-pushed remote background recurse-submodules]
  (default recurse-submodules true)
  (def args @["push"])
  (if recurse-submodules (array/push args "--recurse-submodules=on-demand"))
  (if remote (array/push args remote))
  (if ensure-pushed
    (each relative-submodule-path (ls-submodule-paths dir :recursive true)
      (def submodule-path (path/join dir relative-submodule-path))
      (try
        (do (def unpushed-changes (get-unpushed-changes submodule-path))
            (if (> (length unpushed-changes) 0)
                (push submodule-path)))
        ([err] (print "Skipping " submodule-path " due to " err)))))
  (if background
    (async dir ;args)
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
    (:wait proc))
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

(def- worktree-list-pattern
  (peg/compile ~{:item (replace (* "worktree "
                                   (capture (to "\0")) "\0HEAD "
                                   (capture (to "\0")) "\0branch "
                                   (capture (to "\0\0")) "\0\0")
                                ,|{:path $0 :head $1 :branch $2})
                 :main (some :item)}))

(defn worktree/list [dir] (peg/match worktree-list-pattern (exec-slurp dir "worktree" "list" "--porcelain" "-z")))

(def- branch-status-patt (peg/compile
  ~{:line (replace
            (* (capture (to "\0")) "\0" (capture (to "\0")) "\0" (opt "\n"))
            ,|(case $1
              ">" {:ref $0 :status :ahead}
              "<" {:ref $0 :status :behind}
              "<>" {:ref $0 :status :both}
              "=" {:ref $0 :status :up-to-date}
              (error (string "did not expect " $1 " as %{upstream:trackshort} in for-each-ref message"))))
    :main (some :line)}))

(defn refs/status/short [dir]
  (peg/match branch-status-patt (exec-slurp dir "for-each-ref" "--format=%(refname:short)%00%(upstream:trackshort)%00" "refs/heads")))

(defn refs/status/long [dir]
  (peg/match branch-status-patt (exec-slurp dir "for-each-ref" "--format=%(refname)%00%(upstream:trackshort)%00" "refs/heads")))


(defn refs/status [dir] (refs/status/short dir))

(defn default-branch
  "get the default branch of optional remote"
  [dir &named remote]
  (default remote "origin")
  (let [remote-head-result (exec-slurp-all dir "rev-parse" "--abbrev-ref" (string remote "/HEAD"))]
    (if (= (remote-head-result :code) 0)
      (peg/match ~(* remote "/" (capture (any 1))) (remote-head-result :out))
      (current-branch dir)))) # default to current branch if remote hash no HEAD


(defn interactive-sparse-checkout [dir]
  (def selected-paths @[])
  (def available-paths (distinct (map |(path/dirname $0) (string/split "\0" (exec-slurp dir "ls-tree" "--name-only" "-r" "-z" "HEAD")))))
  (defn add [] (array/push selected-paths (jeff/choose available-paths)))
  (defn rm [] (array/remove selected-paths (index-of (jeff/choose selected-paths) selected-paths)))
  (defn print-help []
    (print `Available Commands:
             add - add a path to list
             rm - remove a path from list
             exit - exit the program aborting all
             done - finish path selection continue with program
             help - show this help`))
  (forever
    (def command (string/trimr (getline "> ")))
    (case command
      "add" (add)
      "a" (add)
      "rm" (rm)
      "remove" (rm)
      "abort" (os/exit 0)
      "exit" (os/exit 0)
      "done" (break)
      "d" (break)
      "end" (break)
      (print-help)))
    (exec "git" "sparse-checkout" "set" ;selected-paths)
    (exec "git" "checkout" "HEAD"))
