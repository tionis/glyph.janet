(use ./config)
(import spork/misc)

(defn modules/add [name path description]
  (config/set (string "module/" name)
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
