(use spork)
(import ./util)

(defn ls []
  (let [scripts-dir (path/join (util/arch-dir) "scripts")
        scripts-dir-stat (os/stat scripts-dir)]
    (if (and scripts-dir-stat (= (scripts-dir-stat :mode) :directory))
        (os/dir scripts-dir)
        [])))

# TODO add pre-sync hook
(defn pre-sync []
  {:error false})

# TODO add post-sync hook
(defn post-sync [])
