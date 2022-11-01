(use ./config)
(import ./git)
(import spork/misc)
(import spork/path)
(import ./scripts)

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

(defn modules/execute [name args]
  (git/async (dyn :arch-dir) "pull")
  (def module (modules/get name))
  (def arch-dir (dyn :arch-dir))
  (if module
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (path/join (dyn :arch-dir) (module :path)))
          (if (os/stat ".main")
            (os/execute [".main" ;args])
            (do (eprint "module has no .main or is not initialized, aborting...") (os/exit 1)))
            # TODO this triggers for modified content and new commits -> only trigger on new commits
            (if ((git/changes arch-dir) (module :path))
                (do (git/loud arch-dir "add" (module :path))
                    (git/loud arch-dir "commit" "-m" (string "updated " name))
                    (git/async arch-dir "push")))))
    (if (index-of name (scripts/ls))
      (do (os/cd (dyn :arch-dir)) (os/execute [(path/join ".scripts" name) ;args]))
      (do (eprint (string "neither a module nor a user script called " name " exists, use help to list existing ones"))
          (os/exit 1)))))
