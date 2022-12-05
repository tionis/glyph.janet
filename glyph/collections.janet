(use ./store)
(import ./git)
(import spork/misc)
(import spork/path)
(import ./scripts)
(import ./util)

(defn collections/add [name description remote]
  (config/set (string "collections/" name)
              {:remote remote :description description}
               :commit-message (string "config: added \"" name "\" module")))

(defn collections/ls [&opt pattern]
 (if (or (not pattern) (= pattern ""))
  (map |(misc/trim-prefix "collections/" $0) (config/ls "collections/*"))
  (map |(misc/trim-prefix "collections/" $0) (config/ls (string "collections/" pattern)))))

(defn collections/rm [name]
  (config/set (string "collections/" name)
              nil
              :commit-message (string "config: removed \"" name "\" collection")))

(defn collections/get [name]
  (def collection (config/get (string "collections/" name)))
  (def cached (cache/get (string "collections/" name))) # TODO replace with call to git worktree
  (def metadata @{:cached (if cached true false)})
  (if (metadata :cached)
    (put metadata :path (cached :path)))
  (merge collection metadata))

(defn collections/init [name path]
  # check if dir exists
  # if exists check if is git dir
  # if is git dir check if origin remote is correct
  # -> add existing

  # use git clone to clone module
  # support git worktree here?
  )

# TODO 2.0 clone or init worktree instead
# TODO 2.0 important: add module to cache

(defn collections/execute [name args]
  (def arch-dir (util/arch-dir))
  (def collection (collections/get name))
  (if (collection :cached)
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (collection :path))
          (if (os/stat ".main")
            (os/execute [".main" ;args])
            (error "collection has no .main or is not initialized"))))
    (if (index-of name (scripts/ls))
      (do (os/cd (util/arch-dir)) (os/execute [(path/join "scripts" name) ;args]))
      (error (string "neither a collection nor a user script called " name " exists")))))
