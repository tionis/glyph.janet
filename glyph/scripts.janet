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

(defn pre-sync []
  (def hook-path (path/join (util/arch-dir) ".git" "hooks" "pre-sync"))
  (let [stat (os/stat hook-path)]
    (if (and stat (= (stat :mode) :file))
      (let [status (os/execute [hook-path])]
        (if (= status 0)
            {:error false}
            {:error true :message "pre-sync hook failed"}))
      {:error false})))

(defn post-sync []
  (def hook-path (path/join (util/arch-dir) ".git" "hooks" "post-sync"))
  (let [stat (os/stat hook-path)]
    (if (and stat (= (stat :mode) :directory))
      (let [status (os/execute [hook-path])]
        (if (= status 0)
            {:error false}
            {:error true :message "post-sync hook failed"})))))

