(use spork)
(import ./git)
(import ./glob)

(defn- create_dirs_if_not_exists [dir]
  (let [meta (os/stat dir)]
    (if (not (and meta (= (meta :mode) :directory)))
      (sh/create-dirs dir))))

(defn- get-config-dir [] (path/join (dyn :arch-dir) ".glyph"))

(defn config/get [key]
  (def path (path/join (get-config-dir) (path/join ;(path/posix/parts key))))
  (let [stat (os/stat path)]
    (if (or (= stat nil) (not (= (stat :mode) :file)))
      nil # Key does not exist
      (parse (slurp path)))))

(defn config/set [key value &named commit-message]
  (def formatted-key (path/join ;(path/posix/parts key)))
  (def path (path/join (get-config-dir) formatted-key))
  (def arch-dir (dyn :arch-dir))
  (if (not value)
    (do
      (def path (path/join (get-config-dir) key))
      (default commit-message (string "config: deleted " key))
      (os/rm path)
      (git/loud arch-dir "reset")
      (git/loud arch-dir "add" "-f" path)
      (git/loud arch-dir "commit" "-m" commit-message))
    (do
      (create_dirs_if_not_exists (path/join (get-config-dir) (path/dirname formatted-key)))
      (default commit-message (string "config: set " key " to " value))
      (spit path (string/format "%j" value))
      (git/loud arch-dir "reset")
      (git/loud arch-dir "add" "-f" path)
      (git/loud arch-dir "commit" "-m" commit-message))))

(defn config/ls [glob-pattern]
  (def config-path (path/join (get-config-dir)))
  (create_dirs_if_not_exists config-path)
  (def ret @[])
  (def prev (os/cwd))
  (os/cd config-path)
  (if (= glob-pattern nil)
    (sh/scan-directory "." |(array/push ret $0))
    (let [pattern (glob/glob-to-peg glob-pattern)]
        (sh/scan-directory "."
                                   |(if (peg/match pattern $0)
                                        (array/push ret $0)))))
  (os/cd prev)
  ret)

(defn config/rm [key] (config/set key nil))

(defn config/ls-contents [glob-pattern]
  (def ret @{})
  (each item (config/ls glob-pattern)
    (put ret item (config/get item)))
  ret)
