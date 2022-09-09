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
