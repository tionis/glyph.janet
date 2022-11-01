(import ./init :prefix "" :export true)
(import ./options)
(use spork)

(defn cli/modules/add [args]
  (def res
    (options/parse
      :description "Add a new module to the glyph archive"
      :options {"name" {:kind :option
                        :required true
                        :short "n"
                        :help "the name of the new module"}
                "path" {:kind :option
                        :required true
                        :short "p"
                        :help "the path of the new module, must be a relative path from the arch_dir root"}
                "description" {:kind :option
                               :required true
                               :short "d"
                               :help "the description of the new module"}}
      :args ["glyph" ;args]))
  (unless res (os/exit 1))
  (modules/add (res "name") (res "path") (res "description"))
  (print `module was added to index. You can now add a .main script and manage it via git.
         For examples for .main script check the glyph main repo at https://tasadar.net/tionis/glyph`))

(defn cli/modules/ls [&opt args]
  (print (string/join (map |(string $0 " - " ((modules/get $0) :description))
                           (modules/ls (first args)))
                      "\n")))

(defn cli/modules/rm [name]
  (if (not name) (do (print "Specify module to remove!") (os/exit 1)))
  (def module (modules/get name))
  (if (not module) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud (dyn :arch-dir) "submodule" "deinit" "-f" (module :path))
  (sh/rm (path/join (dyn :arch-dir) ".git" "modules" (module :path)))
  (modules/rm name)
  (print "module " name " was deleted"))

(defn cli/modules/help []
  (print `Available Subcommands:
           add - add a new module
           ls - list modules
           rm - remove a module
           init - initialize an existing module
           deinit - deinitialize and existing module
           help - show this help`))

(defn cli/modules/init [name]
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (modules/get name))
  (if (not module-conf) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud (dyn :arch-dir) "submodule" "update" "--init" (module-conf :path)))

(defn cli/modules/deinit [name]
  (def arch-dir (dyn :arch-dir))
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (modules/get name))
  (if (not module-conf) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud arch-dir "submodule" "deinit" "-f" (module-conf :path))
  (sh/rm (path/join arch-dir ".git" "modules" (module-conf :path))))

(defn cli/setup [args]
  (print `To setup your own glyph archive you just need to do following things:
           1. create a directory at $GLYPH_ARCH_DIR
           2. use glyph git init to initialize the git repo
           3. add a git remote
           4. add your glyph modules with glyph modules add
           5. profit`))

(defn cli/modules [args]
  (case (first args)
    "add" (cli/modules/add (slice args 1 -1))
    "init" (cli/modules/init (get args 1 nil))
    "deinit" (cli/modules/deinit (get args 1 nil))
    "ls" (cli/modules/ls (get args 1 nil))
    "rm" (cli/modules/rm (get args 1 nil))
    "help" (cli/modules/help)
    nil (cli/modules/ls)
    (modules/execute (first args) (slice args 1 -1))))

(defn cli/scripts [args] (print "To add user scripts just add them in the .scripts directory"))

(defn cli/fsck [args] (fsck))

(defn cli/sync [args] (sync))

(defn print-root-help []
  (def preinstalled `Available Subcommands:
                      modules - manage your custom modules, use 'glyph modules help' for more information
                      scripts - manage your user scripts
                      git - execute git command on the arch repo
                      sync - sync the glyph archive
                      fsck - perform a filesystem check of arch repo
                      help - print this help`)
  (def modules (map |(string "  " $0 " - " ((modules/get $0) :description)) (modules/ls)))
  (def scripts (map |(string "  " $0 " - user script") (scripts/ls)))
  (print (string/join (array/concat @[preinstalled] modules scripts) "\n")))

(defn main [myself & args]
  (def arch-dir (util/get-arch-dir))
  (setdyn :arch-dir arch-dir)
  (case (first args)
    "setup" (cli/setup (slice args 1 -1))
    "modules" (cli/modules (slice args 1 -1))
    "scripts" (cli/scripts (slice args 1 -1))
    "git" (os/exit (os/execute ["git" "-C" arch-dir ;(slice args 1 -1)] :p))
    "fsck" (cli/fsck (slice args 1 -1))
    "sync" (cli/sync (slice args 1 -1))
    "help" (print-root-help)
    "--help" (print-root-help)
    "-h" (print-root-help)
    nil (print-root-help)
    (modules/execute (first args) (slice args 1 -1))))
