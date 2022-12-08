(use spork)
(import ./util)

(defn ls []
  (let [scripts-dir (path/join (util/arch-dir) "scripts")
        scripts-dir-stat (os/stat scripts-dir)]
    (if (and scripts-dir-stat (= (scripts-dir-stat :mode) :directory))
        (os/dir scripts-dir)
        [])))

(defn setup/exec []
  (def script-path (path/join (util/arch-dir) "scripts" "setup"))
  (def script-stat (os/stat script-path))
  (if (and script-path (= (script-stat :mode) :file))
    (os/execute [script-path])
    (print "No setup script found, skipping...")))

# TODO add pre-sync hook
(defn pre-sync []
  {:error false})

# TODO add post-sync hook
(defn post-sync [])
