(use spork/sh)
(import spork/path)

(defn get-null-file "get the /dev/null equivalent for current platform" []
  (case (os/which)
    :windows "NUL"
    :macos "/dev/null"
    :web (error "Unsupported Operation")
    :linux "/dev/null"
    :freebsd "/dev/null"
    :openbsd "/dev/null"
    :posix "/dev/null"))

(defn slurp # TODO put the git handling stuff into its own module
  "given a config and some arguments execute the git subcommand on wiki"
  [dir & args]
  (exec-slurp "git" "-C" dir ;args))

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
  (each line (string/split "\n" (slurp git-repo-dir "status" "--porcelain=v1"))
    (if (and line (not= line ""))
      (let [result (peg/match patt_status_line line)]
        (array/push changes [(status_codes (result 0)) (result 1)]))))
  (def ret @{})
  (each change changes
    (put ret (change 1) (change 0)))
  ret)

(defn async
  "given a config and some arguments execute the git subcommand on wiki asynchroniously"
  [dir & args]
  (def null_file (get-null-file))
  (def fout (os/open null_file :w))
  (def ferr (os/open null_file :w))
  (os/spawn ["git" "-C" dir ;args] :pd {:out fout :err ferr}))

(def- submodules-status-line-peg "pattern to parse a line from git submodules status for it's submodule path"
  (peg/compile ~(* (+ " " "+" "-") (40 :w) " " (<- (to (+ " " -1))) (? (* " " (to -1))))))

(defn ls-submodules
  "lists submodule paths in the repo at dir, if recursive is true this is done recursivly"
  [dir &named recursive]
  (def lines (string/split "\n" (if recursive
                                  (slurp dir "submodule" "status" "--recursive")
                                  (slurp dir "submodule" "status"))))
  (map |(first (peg/match submodules-status-line-peg $0)) lines))

(defn fsck [dir &named no-recurse]
  (print "Executing fsck at root")
  (loud dir "fsck")
  (print)
  (each submodule-path (ls-submodules dir :recursive (not no-recurse))
    (def path (path/join dir submodule-path))
    (print "Executing fsck at " submodule-path)
    (loud path "fsck")
    (print)))
