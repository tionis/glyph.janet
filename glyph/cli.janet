(use ./init)
(import ./options)

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

(defn cli/modules/ls []
  (def pattern (first (dyn :args)))
  (def modules (modules/ls pattern))
  (print
    (string/join
      (map
        (fn [name]
          (def module (config/get (string "module/" name)))
          (string name " - " (module :description))) modules)
      "\n")))

(defn cli/modules/rm [name]
  (if (not name) (do (print "Specify module to remove!") (os/exit 1)))
  (def module (config/get (string "modules/" name)))
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

(defn cli/modules/execute [name args]
  (git/async (dyn :arch-dir) "pull")
  (def module (config/get (string "modules/" name)))
  (def arch-dir (dyn :arch-dir))
  (if module
    (do (def prev-dir (os/cwd))
        (defer (os/cd prev-dir)
          (os/cd (module :path))
          (if (os/stat ".main")
            (os/execute [".main" ;args])
            (do (eprint "module has no .main or is not initialized, aborting...") (os/exit 1)))
            # TODO this triggers for modified content and new commits -> only trigger on new commits
            (if ((git/changes arch-dir) (module :path))
                (do (git/loud arch-dir "add" (module :path))
                    (git/loud arch-dir "commit" "-m" (string "updated " name))
                    (git/async arch-dir "push")))))
    (if (index-of name (scripts/ls))
      (do (os/cd (dyn :arch-dir)) (os/execute [(path/join ".scripts" name) ;args]))
      (do (eprint (string "neither a module nor a user script called " name " exists, use help to list existing ones"))
          (os/exit 1)))))

(defn cli/modules/init [name]
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (config/get (string"modules/" name)))
  (if (not module-conf) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud (dyn :arch-dir) "submodule" "update" "--init" (module-conf :path)))

(defn cli/modules/deinit [name]
  (def arch-dir (dyn :arch-dir))
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (config/get (string"modules/" name)))
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
    "init" (cli/modules/init (first args))
    "deinit" (cli/modules/deinit (first args))
    "ls" (cli/modules/ls)
    "rm" (cli/modules/rm (first args))
    "help" (cli/modules/help)
    nil (cli/modules/ls)
    (cli/modules/execute (first args) (slice args 1 -1))))

(defn cli/scripts [args] (print "To add user scripts just add them in the .scripts directory"))

(defn cli/fsck [args] (fsck))

(defn cli/sync [args] (sync))

(defn print-root-help []
  (def preinstalled `Available Subcommands:
                      modules - manage your custom modules, use 'glyph module --help' for more information
                      scripts - manage your user scripts
                      git - execute git command on the arch repo
                      sync - sync the glyph archive
                      fsck - perform a filesystem check of arch repo
                      help - print this help`)
  (def modules (map |(string "  " $0 " - " (config/get (string "modules/" $0))) (modules/ls)))
  (def scripts (map |(string "  " $0 " - user script") (scripts/ls)))
  (print (string/join (array/concat @[preinstalled] modules scripts) "\n")))

(defn main [myself & args]
  (def arch-dir (do (def env_arch_dir (os/getenv "GLYPH_ARCH_DIR"))
                    (def env_arch_stat (if env_arch_dir (os/stat env_arch_dir) nil))
                    (if (and env_arch_dir (= (env_arch_stat :mode) :directory))
                        env_arch_dir
                        (util/get-default-arch-dir))))
  (setdyn :arch-dir arch-dir)
  (case (first args)
    "setup" (cli/setup (slice args 1 -1))
    "modules" (cli/modules (slice args 1 -1))
    "scripts" (cli/scripts (slice args 1 -1))
    "git" (os/exit (os/execute ["git" "-C" arch-dir ;args] :p))
    "fsck" (cli/fsck (slice args 1 -1))
    "sync" (cli/sync (slice args 1 -1))
    "help" (print-root-help)
    "--help" (print-root-help)
    "-h" (print-root-help)
    nil (print-root-help)
    (cli/modules/execute (first args) (slice args 1 -1))))
