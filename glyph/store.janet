(use spork)
(import ./git)
(import ./glob)
(import ./util)

######### TODO #########
# Add encryption       #
# Add node management  #
# Add signing          #
########################

(defn- create_dirs_if_not_exists [dir]
  (let [meta (os/stat dir)]
    (if (not (and meta (= (meta :mode) :directory)))
      (sh/create-dirs dir))))

(defn- generic/get [base-dir key]
  (def path (path/join base-dir (path/join ;(path/posix/parts key))))
  (let [stat (os/stat path)]
    (if (or (= stat nil) (not (= (stat :mode) :file)))
      nil # Key does not exist
      (parse (slurp path)))))

(defn- generic/set [base-dir key value &named no-git commit-message]
  (def formatted-key (path/join ;(path/posix/parts key)))
  (def path (path/join base-dir formatted-key))
  (def arch-dir (util/arch-dir))
  (if (not value)
    (do
      (def path (path/join base-dir key))
      (default commit-message (string "config: deleted " key))
      (os/rm path)
      (unless no-git
        (git/loud arch-dir "reset")
        (git/loud arch-dir "add" "-f" path)
        (git/loud arch-dir "commit" "-m" commit-message)
        (git/async arch-dir "push")))
    (do
      (create_dirs_if_not_exists (path/join base-dir (path/dirname formatted-key)))
      (default commit-message (string "config: set " key " to " value))
      (spit path (string/format "%j" value))
      (unless no-git
        (git/loud arch-dir "reset")
        (git/loud arch-dir "add" "-f" path)
        (git/loud arch-dir "commit" "-m" commit-message)
        (git/async arch-dir "push")))))

(defn- generic/ls [base-dir &opt glob-pattern]
  (default glob-pattern ".")
  (create_dirs_if_not_exists base-dir)
  (def ret @[])
  (def prev (os/cwd))
  (os/cd base-dir)
  (if (or (string/find "*" glob-pattern)
          (string/find "?" glob-pattern))
    (let [pattern (glob/glob-to-peg glob-pattern)]
         (sh/scan-directory "." |(if (and (= ((os/stat $0) :mode) :file)
                                          (peg/match pattern $0))
                                     (array/push ret $0))))
    (let [glob-stat (os/stat glob-pattern)]
      (if (and glob-stat (= ((glob-stat :mode) :directory)))
          (do (sh/scan-directory glob-pattern |(if (= ((os/stat $0) :mode) :file) (array/push ret $0))))
          @[])))
  (os/cd prev)
  ret)

(defn- generic/ls-contents [base-dir glob-pattern]
  (def ret @{})
  (each item (generic/ls base-dir glob-pattern)
    (put ret item (generic/get base-dir item)))
  ret)

(defn- get-config-dir [] (path/join (util/arch-dir) "config"))
(defn config/get [key] (generic/get (get-config-dir) key))
(defn config/set [key value &named commit-message] (generic/set (get-config-dir) key value :commit-message commit-message))
(defn config/ls [&opt glob-pattern] (generic/ls (get-config-dir) glob-pattern))
(defn config/rm [key] (config/set key nil))
(defn config/ls-contents [glob-pattern] (generic/ls-contents (get-config-dir) glob-pattern))

(defn- get-cache-dir [] (path/join (util/arch-dir) ".git/glyph/cache"))
(defn cache/get [key] (generic/get (get-cache-dir) key))
(defn cache/set [key value &named commit-message] (generic/set (get-cache-dir) key value :no-git true :commit-message commit-message))
(defn cache/ls [&opt glob-pattern] (generic/ls (get-cache-dir) glob-pattern))
(defn cache/rm [key] (cache/set key nil))
(defn cache/ls-contents [glob-pattern] (generic/ls-contents (get-cache-dir) glob-pattern))
