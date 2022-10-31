(use ./config)

(defn add [name path description]
  (config/set (string "module/" name)
              {:path path :description description}
              :commit-message (string "config: added \"" name "\" module")))

(defn ls [&opt pattern]
  (if (or (not pattern) (= pattern ""))
    (config/ls "modules/*")
    (config/ls (string "modules/" pattern))))

(defn rm [name]
  (config/set (string "modules/" name)
              nil
              :commit-message (string "config: removed \"" name "\" module")))
