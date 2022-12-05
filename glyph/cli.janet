(import ./init :prefix "" :export true)
(import ./options :export true)
(use spork)

# TODO 2.0 for cosmo integration
# support a module that has different git dir and working dir
# add some functionalty to generate a prompt efficiently (maybe integrate cosmo into core?)
# add sync status management
# add pre-sync and post-sync hooks?
# write hosts db script?
# add setup and node management logic to core config and node management
# add message management
# add sigchain
# add universal vars


(defn sync/status []
  (if (cosmo/sync/enabled?)
    (os/exit 0)
    (os/exit 1)))

(defn sync/status/print []
  (if (cosmo/sync/enabled?)
    (print "Sync enabled!")
    (print "Sync disabled!")))

(defn get_prompt []
  (def sync_status (if (cosmo/sync/enabled?) "" "sync:disabled "))
  (def changes_array (string/split "\n" ((cosmo/git "status" "--porcelain=v1") :text)))
  (var changes_count (length changes_array))
  (if (= changes_count 1) (if (= (changes_array 0) "") (set changes_count 0)))
  (def changes_status (if (> changes_count 0) (string changes_count " uncommitted changes ")))
  (prin "\x1b[31m" sync_status changes_status "\x1b[37m")(flush))

(def store/help
  `Store allows storing objects and strings in the cosmo git repo, available subcommands are:
    get $KEY - Prints the value for key without extra newline
    set $KEY $VALUE - Set a key to the given value
    ls $OPTIONAL_PATTERN - If glob-pattern was given, list all keys matching it, else list all
    rm $KEY - Delete the key`)

(def store/argparse
  ["Store allows storing objects and strings in the cosmo git repo"
   "global" {:kind :flag
             :short "g"
             :help "Work on global store, this is the default"}
   "local" {:kind :flag
            :short "l"
            :help "Work on local store"}
   "groups" {:kind :accumulate
             :short "t"
             :help "The groups the secret should be encrypted for (implies --global)"}
   :default {:kind :accumulate
             :help store/help}])

(defn print_val [val]
  (if (or (= (type val) :string) (= (type val) :buffer))
      (print val)
      (print (string/format "%j" val))))

(defn store/handler [args]
  (setdyn :args @[((dyn :args) 0) ;(slice (dyn :args) 2 -1)])
  (def args (argparse/argparse ;store/argparse))
  (unless args (os/exit 1))
  (if (not (args :default))
    (do (print store/help)
        (os/exit 0)))
  # TODO pass --groups to store once encryption support is there
  (if (args "groups") (put args "global" true))
  (if (args "global") (put args "local" nil))
  (case ((args :default) 0)
    "get" (if (args "local")
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/cache/get ((args :default) 1))]
                (print_val val)))
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/store/get ((args :default) 1))]
                (print_val val))))
    "set" (if (args "local")
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/cache/set ((args :default) 1) ((args :default) 2))) # TODO 2.0 try parsing the value as JDN?
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/store/set ((args :default) 1) ((args :default) 2)))) # TODO 2.0 try parsing the value as JDN?
    "ls"  (if (args "local") # TODO think of better way for passing list to user (human readable key=value but if --json is given print list as json?)
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/cache/ls-contents patt)]
              (print (string/format "%P" list)))
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/store/ls-contents patt)]
              (print (string/format "%P" list))))
    "rm"  (if (args "local")
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/cache/rm ((args :default) 1)))
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/store/rm ((args :default) 1))))
    (do (eprint "Unknown subcommand")
        (os/exit 1))))

(def universal-vars/help
  `Universal vars are environment variables that are sourced at the beginning of a shell session.
  This allows to have local env-vars that are either machine specific or shared among all.
  To create an environment variable use the store, all variables are stored under the vars/* prefix
  Available Subcommands:
    export $optional_pattern - return the  environment variables matching pattern, all if none is given in a format that can be evaled by posix shells`)

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
         For examples for .main script check the glyph main repo at https://tasadar.net/tionis/glyph
         If this glyph module uses a git submodule ensure that the git module update and branch are set 
         these .gitmodule options ensure the gitmodules are handled correctly by all glyph functions`))

(defn cli/modules/ls [&opt args]
  (print (string/join (map |(string $0 " - " ((modules/get $0) :description))
                           (modules/ls (first args)))
                      "\n")))

(defn cli/modules/rm [name]
  # TODO 2.0 change to nuke
  (if (not name) (do (print "Specify module to remove!") (os/exit 1)))
  (def module (modules/get name))
  (if (not module) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud (util/arch-dir) "submodule" "deinit" "-f" (module :path))
  (sh/rm (path/join (util/arch-dir) ".git" "modules" (module :path)))
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
  # TODO 2.0 just call modules/init
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (modules/get name))
  (if (not module-conf) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (modules/init name))

(defn cli/modules/deinit [name]
  # TODO 2.0 just call modules/deinit
  (def arch-dir (util/arch-dir))
  (if (not name) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-conf (modules/get name))
  (if (not module-conf) (do (print "Module " name " not found, aborting...") (os/exit 1)))
  (git/loud arch-dir "submodule" "deinit" "-f" (module-conf :path))
  (sh/rm (path/join arch-dir ".git" "modules" (module-conf :path))))


(def store/help
  `Store allows storing objects and strings in the cosmo git repo, available subcommands are:
    get $KEY - Prints the value for key without extra newline
    set $KEY $VALUE - Set a key to the given value
    ls $OPTIONAL_PATTERN - If glob-pattern was given, list all keys matching it, else list all
    rm $KEY - Delete the key`)

(def store/argparse
  ["Store allows storing objects and strings in the cosmo git repo"
   "global" {:kind :flag
             :short "g"
             :help "Work on global store, this is the default"}
   "local" {:kind :flag
            :short "l"
            :help "Work on local store"}
   "groups" {:kind :accumulate
             :short "t"
             :help "The groups the secret should be encrypted for (implies --global)"}
   :default {:kind :accumulate
             :help store/help}])

(defn print_val [val]
  (if (or (= (type val) :string) (= (type val) :buffer))
      (print val)
      (print (string/format "%j" val))))

(defn store/handler [args]
  (setdyn :args @[((dyn :args) 0) ;(slice (dyn :args) 2 -1)])
  (def args (argparse/argparse ;store/argparse))
  (unless args (os/exit 1))
  (if (not (args :default))
    (do (print store/help)
        (os/exit 0)))
  # TODO pass --groups to store once encryption support is there
  (if (args "groups") (put args "global" true))
  (if (args "global") (put args "local" nil))
  (case ((args :default) 0)
    "get" (if (args "local")
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/cache/get ((args :default) 1))]
                (print_val val)))
            (do
              (if (< (length (args :default)) 2) (error "Key to get not specified"))
              (let [val (cosmo/store/get ((args :default) 1))]
                (print_val val))))
    "set" (if (args "local")
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/cache/set ((args :default) 1) ((args :default) 2)))
            (do (if (< (length (args :default)) 3) (error "Key or value to set not specified"))
              (cosmo/store/set ((args :default) 1) ((args :default) 2))))
    "ls"  (if (args "local") # TODO think of better way for passing list to user (human readable key=value but if --json is given print list as json?)
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/cache/ls-contents patt)]
              (print (string/format "%P" list)))
            (let [patt (if (> (length (args :default)) 1) (string/join (slice (args :default) 1 -1) "/") nil)
                list (cosmo/store/ls-contents patt)]
              (print (string/format "%P" list))))
    "rm"  (if (args "local")
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/cache/rm ((args :default) 1)))
            (do (if (< (length (args :default)) 2) (error "Key to delete not specified"))
              (cosmo/store/rm ((args :default) 1))))
    (do (eprint "Unknown subcommand")
        (os/exit 1))))

(defn cli/setup/modules [args]
  (error "Not implemented yet")) # TODO implement modules setup using jeff multi select

(defn cli/setup/help [args]
  (print `To setup your own glyph archive you just need to do following things:
           1. create a directory at $GLYPH_ARCH_DIR
           2. use glyph git init to initialize the git repo
           3. add a git remote
           4. add your glyph modules with glyph modules add
           5. profit
         If you already have a glyph repo setup you can simply clone it via git clone.
         After cloning use glyph setup modules to set up your modules`))

(defn cli/setup [args]
  (case (first args)
    "modules" (cli/setup/modules (slice args 1 -1))
    "help" (cli/setup/help (slice args 1 -1))
    (cli/setup/help (slice args 1 -1))))

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

(defn cli/daemon/sync [args]
  (case (first args)
    "enable" (daemon/sync/enable)
    "disable" (daemon/sync/disable)
    "status" (if (daemon/sync/status) (print "daemon sync enabled") (print "daemon sync disabled"))
    (print `Unknown command, available commands are:
             enable - enable the daemon sync
             disable - disable the daemon sync
             status - show the status of daemon-based sync setting`)))

(defn cli/daemon/status [args]
  (if (daemon/check)
    (do (print "daemon is running") (os/exit 0))
    (do (print "daemon not running") (os/exit 1))))

(defn cli/daemon [args]
  (case (first args)
    "sync" (cli/daemon/sync (slice args 1 -1))
    "status" (cli/daemon/status (slice args 1 -1))
    "ensure" (daemon/ensure)
    "launch" (daemon/launch)
    (print `Unknown command, available commands are:
             sync - configure the daemon-based sync
             launch - launch the daemon
             ensure - ensure the daemon is running
             status - query the status of the daemon`)))

(defn cli/scripts [args] (print "To add user scripts just add them in the .scripts directory"))

(defn cli/fsck [args] (fsck))

(defn cli/sync [args] (sync))

(defn cli/tools/ensure-pull-merges-submodules # TODO 2.0 remove?
  []
  (git/submodules/update/set (util/arch-dir) "merge" :show-message true :recursive true))

(defn cli/tools [args]
  (case (first args)
    "ensure-pull-merges-submodules" (cli/tools/ensure-pull-merges-submodules)
    (print `Unknown command! Available commands:
             ensure-pull-merges-submodules - ensure that new commits in submodules are merged in rather than checked out via the submodule.NAME.update git config option. this is done recursively.`)))

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
  (unless (let [stat (os/stat arch-dir)] (and stat (= (stat :mode) :directory)))
    (eprint "Arch dir does not exist, please initialize it first!")
    (print "Short setup description:")
    (cli/setup/help [])
    (print "For more information please refer to the glyph documentation")
    (os/exit 1))
  (setdyn :arch-dir arch-dir)
  (case (first args)
    # TODO 2.0 add store command (or both a config and a cache command? steal code from cosmo)
    "setup" (cli/setup (slice args 1 -1))
    "modules" (cli/modules (slice args 1 -1))
    "scripts" (cli/scripts (slice args 1 -1))
    "daemon" (cli/daemon (slice args 1 -1))
    "git" (os/exit (os/execute ["git" "-C" arch-dir ;(slice args 1 -1)] :p))
    "fsck" (cli/fsck (slice args 1 -1))
    "sync" (cli/sync (slice args 1 -1))
    "tools" (cli/tools (slice args 1 -1))
    "help" (print-root-help)
    "--help" (print-root-help)
    "-h" (print-root-help)
    nil (print-root-help)
    (modules/execute (first args) (slice args 1 -1))))
