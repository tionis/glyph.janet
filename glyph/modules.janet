(use ./store)
(import ./git)
(import spork/misc)
(import spork/path)
(import ./scripts)
(import ./util)

(defn modules/add [name path description]
  (config/set (string "modules/" name)
              {:path path :description description}
              :commit-message (string "config: added \"" name "\" module")))

(defn modules/ls [&opt pattern]
  (if (or (not pattern) (= pattern ""))
    (map |(misc/trim-prefix "modules/" $0) (config/ls "modules/*"))
    (map |(misc/trim-prefix "modules/" $0) (config/ls (string "modules/" pattern)))))

(defn modules/rm [name]
  (config/set (string "modules/" name)
              nil
              :commit-message (string "config: removed \"" name "\" module")))

(defn modules/get [name] (config/get (string "modules/" name)))

(defn modules/init [name] (git/loud (util/arch-dir) "submodule" "update" "--init" ((modules/get name) :path))) # TODO 2.0 clone instead
# TODO 2.0 important: add module to cache

# TODO 2.0 add cache auto update

(defn modules/execute [name args] # TODO 2.0 no auto commit
  (def arch-dir (util/arch-dir))
  (git/pull arch-dir :background true)
  (def module (modules/get name))
  (if module
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (path/join (util/arch-dir) (module :path)))
          (if (os/stat ".main")
            (os/execute [".main" ;args])
            (do (eprint "module has no .main or is not initialized, aborting...") (os/exit 1)))
            # TODO this triggers for modified content and new commits -> only trigger on new commits
            (if ((git/changes arch-dir) (module :path))
                (do (git/loud arch-dir "add" (module :path))
                    (git/loud arch-dir "commit" "-m" (string "updated " name))
                    (git/push arch-dir :background true)))))
    (if (index-of name (scripts/ls))
      (do (os/cd (util/arch-dir)) (os/execute [(path/join ".scripts" name) ;args]))
      (do (eprint (string "neither a module nor a user script called " name " exists, use help to list existing ones"))
          (os/exit 1)))))
