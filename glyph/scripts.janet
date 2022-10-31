(use spork)

(defn ls []
  (let [scripts-dir (path/join (dyn :arch-dir) ".scripts")
        scripts-dir-stat (os/stat scripts-dir)]
    (if (and scripts-dir-stat (= (scripts-dir-stat :mode) :directory))
        (os/dir scripts-dir)
        [])))
