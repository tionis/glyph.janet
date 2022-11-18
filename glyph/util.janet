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

(defn get-default-arch-dir [] (path/join (home) "arch"))

(defn get-arch-dir []
  (or (os/getenv "GLYPH_ARCH_DIR")
      (get-default-arch-dir)))

(defn arch-dir []
  (if (not (dyn :arch-dir)) (setdyn :arch-dir (get-arch-dir)))
  (dyn :arch-dir))
