(use ./store)
(import ./git)
(import spork/misc)
(import spork/path)
(import spork/json)
(import ./scripts)
(import ./util)

(defn collections/add [name description remote remote-branch]
  (config/set (string "collections/" name)
              {:remote remote :description description :remote-branch remote-branch}
               :commit-message (string "config: added \"" name "\" module")))

(defn collections/ls [&opt pattern]
 (if (or (not pattern) (= pattern ""))
  (map |(misc/trim-prefix "collections/" $0) (config/ls "collections/*"))
  (map |(misc/trim-prefix "collections/" $0) (config/ls (string "collections/" pattern)))))

(defn collections/nuke [name]
  (config/set (string "collections/" name)
              nil
              :commit-message (string "config: removed \"" name "\" collection")))

(defn collections/get [name]
  # this, collections/init and collections/deinit are the only parts of the collections integration that have a hard dependency on git worktrees
  # if normal repos are to be used in the future modify these two functions
  (label result
    (def collection (config/get (string "collections/" name)))
    (unless collection (return result nil))
    (def cached (first (filter |(= ($0 :branch) (string "refs/heads/" name)) (git/worktree/list (util/arch-dir)))))
    (def metadata @{:cached (if cached true false)})
    (if (metadata :cached) (merge-into metadata cached))
    (return result (merge collection metadata))))

(defn collections/init [name path]
  (def collection (collections/get name))
  (if (collection :cached) (error "collection already initialized"))
  (def arch-dir (util/arch-dir))
  (git/loud (util/arch-dir) "config" "push.default" "upstream") # TODO hotfix remove later
  (try
    (git/exec-slurp arch-dir "remote" "add" name (collection :remote))
    ([err] (if (not= (git/exec-slurp arch-dir "remote" "get-url" name) (collection :remote))
             (error "remote with same name as collection already exists"))))
  (git/loud arch-dir "fetch" name (string (collection :remote-branch) ":" name))
  (git/loud arch-dir "branch" (string "--set-upstream-to=" name "/" (collection :remote-branch)) name)
  (git/loud arch-dir "worktree" "add" path name))

(defn collections/deinit [name]
  (def collection (collections/get name))
  (unless (collection :cached) (error "collection not initialized"))
  (git/loud (util/arch-dir) "worktree" "remove" (collection :path))
  (print "Collection deinitialized")) # TODO add note about deleting it and reclaiming disk space with git lfs prune/git gc deleting branch etc. (maybe add collections/gc?)

(defn collections/execute [name args]
  (def arch-dir (util/arch-dir))
  (def collection (collections/get name))
  (if (and collection (collection :cached))
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (collection :path))
          (if (os/stat ".main")
            (os/execute [".main" ;args])
            (error "collection has no .main or is not initialized"))))
    (if (index-of name (scripts/ls))
      (do (os/cd (util/arch-dir)) (os/execute [(path/join "scripts" name) ;args]))
      (error (string "neither a collection nor a user script called " name " exists")))))

(defn collections/sync []
  (each collection (filter |($0 :cached) (map |(merge (collections/get $0) {:name $0}) (collections/ls)))
    (def info-path (path/join (collection :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (index-of "sync" (info "supported"))
                (do (print "Starting additional sync for " (collection :name))
                    (collections/execute (collection :name) ["sync"])))))))

(defn collections/fsck []
  (each name (collections/ls)
    (def collection (collections/get name))
    (def info-path (path/join (collection :path) ".main.info.json"))
    (if (os/stat info-path)
        (do (def info (json/decode (slurp info-path)))
            (if (index-of "fsck" (info "supported"))
                (do (print "Starting additional fsck for " name)
                    (collections/execute name ["fsck"])))))))
