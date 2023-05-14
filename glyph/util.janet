(use spork)
(defn no-ext
  [file-path]
  (if (string/find "." file-path)
      (when file-path
        (if-let [rev (string/reverse file-path)
                 dot (string/find "." rev)]
          (string/reverse (string/slice rev (inc dot)))
          file-path))
      file-path))

(defn only-ext
  [file-path]
  (when file-path
    (if-let [rev (string/reverse file-path)
             dot (string/find "." rev)]
      (string/reverse (string/slice rev 0 (inc dot)))
      file-path)))

(defn home []
  (def p (os/getenv "HOME"))
  (if (or (not p) (= p ""))
      (let [userprofile (os/getenv "USERPROFILE")]
           (if (or (not userprofile) (= userprofile ""))
               (error "Could not determine home directory")
               userprofile))
      p))

(defn get-default-arch-dir [] (path/join (home) ".glyph"))

(defn get-arch-dir []
  (or (os/getenv "GLYPH_DIR")
      (get-default-arch-dir)))

(defn arch-dir []
  (if (not (dyn :arch-dir)) (setdyn :arch-dir (get-arch-dir)))
  (dyn :arch-dir))

(def minimum-git-version [2 36 0])

(defn is-at-least-version [actual at-least]
  (label is-at-least
    (loop [i :range [0 (min (length actual) (length at-least))]]
      (cond
        (> (actual i) (at-least i)) (return is-at-least true)
        (< (actual i) (at-least i)) (return is-at-least false)))
    true))

(def git-version-grammar (peg/compile
  ~{:patch (number (some :d))
    :minor (number (some :d))
    :major (number (some :d))
    :main (* "git version " :major "." :minor "." :patch)}))

(defn get-git-version []
  (peg/match git-version-grammar (sh/exec-slurp "git" "--version")))

(defn check-deps []
  (when (not (dyn :deps-checked))
    (unless (is-at-least-version (get-git-version) minimum-git-version)
      (error (string "minimum-git-version is "
                     (string/join (map |(string $0)
                                       minimum-git-version) ".")
                     " but detected git version is "
                     (string/join (map |(string $0)
                                       (get-git-version)) "."))))
    (setdyn :deps-checked true)))
