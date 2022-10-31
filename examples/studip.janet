#!/bin/env janet
(import http)
(use glyph/helpers)

(defn log [x] (print (string/format "%P" x)) x)

(defn studip/get-no-parse [& path-components]
  (def prefix "/studip/api.php")
  (def path (misc/trim-prefix prefix (string/join path-components)))
  (def resp (http/get (string "https://studip.uni-passau.de/studip/api.php" path) :headers (dyn :headers)))
  (if (= (resp :status) 200)
      (resp :body)
      (error (string "error in studip/get:" (string/format "%j" resp)))))

(defn studip/get [& path-components]
  (def prefix "/studip/api.php")
  (def path (misc/trim-prefix prefix (string/join path-components)))
  (def resp (http/get (string "https://studip.uni-passau.de/studip/api.php" path) :headers (dyn :headers)))
  (if (= (resp :status) 200)
      (json/decode (resp :body))
      (error (string "error in studip/get:" (string/format "%j" resp)))))

(defn select-semester [studip-dir config]
  (def semesters ((studip/get "/semesters") "collection"))
  (def chosen (jeff/choose "semester> " (map |($0 "description") semesters)))
  (def selected-semester (filter |(= ($0 "description") chosen) semesters))
  (put config :semester-id ((first selected-semester) "id"))
  (spit (path/join studip-dir ".config.jdn") (string/format "%j" config))
  (def cwd (os/cwd))
  (if (>= (length (git/changes cwd)) 0)
    (do (git/loud cwd "add" ".config.jdn")
        (git/loud cwd "commit" "-m" "selected new semester")
        (git/async cwd "push"))))

(defn sync [studip-dir semester-id]
  (def user-id ((studip/get "/user") "user_id"))

  (defn get-subfolders [folder]
    (def subfolders ((studip/get "/folder/" (folder "id") "/subfolders") "collection"))
    (put folder "files" ((studip/get "/folder/" (folder "id") "/files") "collection"))
    (put folder "subfolders" @[])
    (each subfolder subfolders
      (array/push (folder "subfolders") (get-subfolders)))
    folder)

  (def courses
    (map (fn [x]
           (def path (get-in x ["modules" "documents"]))
           (if path
             (put x "top_folder" (studip/get path)))
           (if (get-in x ["top_folder" "id"])
               (put-in x ["top_folder" "files"] ((studip/get "/folder/" (get-in x ["top_folder" "id"]) "/files") "collection")))
           (if (get-in x ["top_folder" "subfolders"])
               (let [subfolders @[]]
                 (each subfolder (get-in x ["top_folder" "subfolders"])
                   (array/push subfolders (get-subfolders subfolder)))
                 (put-in x ["top_folder" "subfolders"] subfolders)))
             x) (if semester-id
                    ((studip/get "/user/" user-id "/courses?semester=" semester-id) "collection")
                    ((studip/get "/user/" user-id "/courses") "collection"))))

  (defn get-files [folder parent-path]
    (def files @{})
    (each file (folder "files")
      (put files (string/join [parent-path (file "name")] "/") (file "id")))
    (if (folder "subfolders")
      (each subfolder (folder "subfolders")
        (merge-into files (get-files subfolder (string parent-path "/" (subfolder "name"))))))
    files)

  (def files @{})
  (each course courses
    (if (course "top_folder")
      (merge-into files (get-files (course "top_folder") (course "title")))))

  (each file (keys files)
    (def file-path (path/join studip-dir file))
    (if (not (os/stat file-path))
      (do
        (let [file-dir (path/dirname file-path)]
          (if (not (os/stat file-dir))
            (do (print "Creating " file-dir)
                (sh/create-dirs file-dir))))
        (print "Downloading " file)
        (def file-meta (studip/get "/file/" (files file)))
        (if (file-meta "url")
          (spit file-path (string/format "%j" file-meta))
          (spit file-path (studip/get-no-parse "/file/" (files file) "/download"))))))
  (def cwd (os/cwd))
  (if (> (length (git/changes cwd)) 0)
    (do (git/loud cwd "add" "-A")
        (git/loud cwd "commit" "-m" "synced new files")
        (git/async cwd "push"))))

(defn help []
  (print `Available commands:
           help - show this help
           sync - sync the selected semester
           select-semester - select a new semester`))

(defn main [myself & args]
  (def cwd (os/cwd))
  (git/async cwd "pull")
  (def studip-dir (os/cwd))

  (if (not (os/stat (path/join studip-dir ".config.jdn")))
      (do (print "config not found, please set a cookie and select a semester before first use using the respective subcommands!")
          (os/exit 1)))

  (def config (parse (slurp (path/join studip-dir ".config.jdn"))))
  (def firefox-dir (path/join (os/getenv "HOME") ".mozilla" "firefox"))
  (def firefox-profile-dir
    (path/join firefox-dir
      (first (filter |(peg/match ~(* (* (any (* (not ".default-release") 1)) ".default-release") -1) $0)
                     (os/dir firefox-dir)))))
  (setdyn :headers {"Cookie" (string "Seminar_Session=" ((first (filter |(and (= ($0 "name") "Seminar_Session") (= ($0 "host") "studip.uni-passau.de")) ((json/decode (sh/exec-slurp "dejsonlz4" (path/join firefox-profile-dir "sessionstore-backups" "recovery.jsonlz4"))) "cookies"))) "value"))})
  (if (not= ((os/stat studip-dir) :mode) :directory) (error "studip-dir does not exist or is not a dir"))

  (case (first args)
    "select-semester" (select-semester studip-dir config)
    "sync" (sync studip-dir (config :semester-id))
    "shell" (shell studip-dir (slice args 1 -1))
    nil (help)
    "help" (help)
    (error "Could not parse args")))
