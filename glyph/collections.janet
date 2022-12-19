(use ./store)
(import ./git)
(import spork/misc)
(import spork/path)
(import spork/json)
(import ./scripts)
(import ./util)

(defn collections/add [name description remote remote-branch]
  (store/set (string "collections/" name)
              {:remote remote :description description :remote-branch remote-branch}
               :commit-message (string "store: added \"" name "\" module")))

(defn collections/ls [&opt pattern]
 (if (or (not pattern) (= pattern ""))
  (map |(misc/trim-prefix "collections/" $0) (store/ls "collections"))
  (map |(misc/trim-prefix "collections/" $0) (store/ls (string "collections/" pattern)))))

(defn collections/nuke [name]
  (store/set (string "collections/" name)
              nil
              :commit-message (string "store: removed \"" name "\" collection")))

(defn collections/get [name]
  # this, collections/init and collections/deinit are the only parts of the collections integration that have a hard dependency on git worktrees
  # if normal repos are to be used in the future modify these two functions
  (label result
    (def collection (store/get (string "collections/" name)))
    (unless collection (return result nil))
    (def cached (first (filter |(= ($0 :branch) (string "refs/heads/" name)) (git/worktree/list (util/arch-dir)))))
    (def metadata @{:cached (if cached true false)})
    (if (metadata :cached) (merge-into metadata cached))
    (return result (merge collection metadata))))

(defn- is-executable [stat]
  (or (= ((stat :permissions) 2) 120)
      (= ((stat :permissions) 5) 120)
      (= ((stat :permissions) 8) 120)))

(defn collections/execute [name args]
  (def arch-dir (util/arch-dir))
  (def collection (collections/get name))
  (if (and collection (collection :cached))
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (collection :path))
          (def stat (os/stat ".main"))
          (if (and stat (= (stat :mode) :file))
            (if (is-executable stat)
              (os/execute [".main" ;args])
              (if (os/stat ".main.info.json")
                (let [info (json/decode (slurp ".main.info.json"))]
                  (if (info "interpreter")
                    (os/execute [;(info "interpreter") ".main" ;args] :p)
                    (error "collections .main file is not executable and no fallback could be found")))
                (error "collections .main file is not executable and no fallback could be found")))
            (error "collection has no .main or is not initialized"))))
    (if (index-of name (scripts/ls))
      (do (os/cd (util/arch-dir)) (os/execute [(path/join "scripts" name) ;args]))
      (error (string "neither a collection nor a user script called " name " exists")))))

(defn collections/init [name path]
  (def collection (collections/get name))
  (if (collection :cached) (error "collection already initialized"))
  (def arch-dir (util/arch-dir))
  (git/loud (util/arch-dir) "store" "push.default" "upstream") # TODO hotfix remove later
  (try
    (git/exec-slurp arch-dir "remote" "add" name (collection :remote))
    ([err] (if (not= (git/exec-slurp arch-dir "remote" "get-url" name) (collection :remote))
             (error "remote with same name as collection already exists"))))
  (git/loud arch-dir "fetch" name (string (collection :remote-branch) ":" name))
  (git/loud arch-dir "branch" (string "--set-upstream-to=" name "/" (collection :remote-branch)) name)
  (git/loud arch-dir "worktree" "add" path name)
  (def info-path (path/join path ".main.info.json"))
  (if (os/stat info-path)
      (do (def info (json/decode (slurp info-path)))
          (if (get-in info ["supported" "setup"])
              (do (print "Starting additional sync for " (collection :name))
                  (collections/execute (collection :name) (get-in info ["supported" "setup"]))))))
  # TODO detect if the filesystem at path does not support executable flag
  # if it doesn't call (git/loud path config core.fileMode false)
  )

(defn collections/deinit [name]
  (def collection (collections/get name))
  (unless (collection :cached) (error "collection not initialized"))
  (git/loud (util/arch-dir) "worktree" "remove" (collection :path))
  (print "Collection deinitialized")) # TODO add note about deleting it and reclaiming disk space with git lfs prune/git gc deleting branch etc. (maybe add collections/gc?)

(defn collections/sync []
  (each collection (filter |($0 :cached) (map |(merge (collections/get $0) {:name $0}) (collections/ls)))
    (def info-path (path/join (collection :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (get-in info ["supported" "sync"])
                (do (print "Starting additional sync for " (collection :name))
                    (collections/execute (collection :name) (get-in info ["supported" "sync"]))))))))

(defn collections/fsck []
  (each name (collections/ls)
    (def collection (collections/get name))
    (def info-path (path/join (collection :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (get-in info ["supported" "fsck"])
                (do (print "Starting additional fsck for " name)
                    (collections/execute name (get-in info ["supported" "fsck"]))))))))
