(use spork)

(defn ls []
  (let [scripts-dir (path/join (dyn :arch-dir) ".scripts")
        scripts-dir-stat (os/stat scripts-dir)]
    (if (and scripts-dir-stat (= (scripts-dir-stat :mode) :directory))
        (os/dir scripts-dir)
        [])))

(defn sync/ls []
  (let [scripts-dir (path/join (dyn :arch-dir) ".sync")
        scripts-dir-stat (os/stat scripts-dir)]
    (if (and scripts-dir-stat (= (scripts-dir-stat :mode) :directory))
        (os/dir scripts-dir)
        [])))

(defn sync/exec []
  (os/cd (dyn :arch-dir))
  (each script (sync/ls)
    (def path (path/join (dyn :arch-dir) ".sync" script))
    (def return-code (os/execute [path]))
    (if (not= return-code 0) (error (string "sync script " script " failed")))))
