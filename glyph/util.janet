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
  (def env_arch_dir (os/getenv "GLYPH_ARCH_DIR"))
  (def env_arch_stat (if env_arch_dir (os/stat env_arch_dir) nil))
  (if (and env_arch_dir (= (env_arch_stat :mode) :directory))
      env_arch_dir
      (get-default-arch-dir)))
