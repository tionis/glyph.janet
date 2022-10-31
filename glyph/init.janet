#!/bin/env janet
(import flock)
(import chronos :as "date" :export true)
(import spork :prefix "" :export true)
(import uri :export true)
(import ./glob :export true)
#(use ./log-item) # disabled due to being unfinished
(import fzy :as "fzy" :export true)
(import jeff/ui :as "jeff" :export true)
(import ./util :export true)
(import ./git :export true)

(defn sync
  "synchronize arch specified by config synchroniously"
  [config]
  # TODO sync all modules
  (os/execute ["git" "-C" (config :arch-dir) "pull"] :p)
  (os/execute ["git" "-C" (config :arch-dir) "push"] :p))

(defn- config/load [arch-dir]
  (def conf-path (path/join arch-dir ".glyph" "config.jdn"))
  (try (parse (slurp conf-path))
       ([err] (error "Could not parse glyph config"))))

(defn config/eval [arch-dir eval-func &opt commit-message]
  (def conf-path (path/join arch-dir ".glyph" "config.jdn"))
  (with [lock (flock/acquire conf-path :block :exclusive)]
    (def old-conf (config/load arch-dir))
    (def new-conf (eval-func old-conf))
    (spit conf-path (string/format "%j" new-conf))
    (git/loud arch-dir "reset")
    (git/loud arch-dir "add" ".glyph/config.jdn")
    (default commit-message "config: updated config")
    (git/loud arch-dir "commit" "-m" commit-message)
    (flock/release lock)))

(defn module/add [arch-dir root-conf name path description]
  (def posix-path (path/posix/join ;(path/parts path)))
  (sh/create-dirs (path/join arch-dir ;(path/posix/parts posix-path)))
  (config/eval
    arch-dir
    (fn [x]
      (put-in x [:modules name :path] posix-path)
      (put-in x [:modules name :description] description)
      x)
    (string "config: added new module " name " at " path)))

(defn cli/modules/add [arch-dir root-conf]
  (def res
    (argparse/argparse
      "Add a new module to the glyph archive"
      "name" {:kind :option
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
                     :help "the description of the new module"}))
  (unless res (os/exit 1))
  (module/add arch-dir root-conf (res "name") (res "path") (res "description"))
  (print `module was added to index. You can now add a .main script and manage it via git.
         For examples for .main script check the glyph main repo at https://tasadar.net/tionis/glyph`))

(defn module/ls [arch-dir root-conf &opt glob-pattern]
  (default glob-pattern "*")
  (def pattern (glob/glob-to-peg glob-pattern))
  (def ret @[])
  (eachk k (root-conf :modules)
    (if (peg/match pattern k) (array/push ret k)))
  ret)

(defn cli/modules/ls [arch-dir root-conf]
  (def res
    (argparse/argparse
      "List modules with an optional pattern"
      "output" {:kind :option
                :short "o"
               :help "Output format, valid options are jdn, jsonl, pretty"}
      :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (def pattern (first (res :default)))
  (def modules (module/ls arch-dir root-conf pattern))
  (case (res "output")
    "jdn" (print (string/join (map |(string/format "%j" (get-in root-conf [:modules $0])) modules) "\n"))
    "jsonl" (print (string/join (map |(json/encode (get-in root-conf [:modules $0])) modules) "\n"))
    "pretty" (print (string/join (map |(string/format "%P" (get-in root-conf [:modules $0])) modules) "\n"))
    (print (string/join (map |(string $0 " - " (get-in root-conf [:modules $0 :description])) modules) "\n"))))

(defn module/rm [arch-dir root-conf module-name]
  (config/eval
    arch-dir
    (fn [x] (put-in x [:modules module-name] nil) x)
    (string "config: removed module " module-name)))

(defn cli/modules/rm [arch-dir root-conf]
  (def res
    (argparse/argparse
      "remove a module"
      :default {:kind :accumulate}))
  (unless res (os/exit 1))
  (if (= (length (res :default)) 0) (do (print "Specify module to remove!") (os/exit 1)))
  (def module-name ((res :default) 0))
  (if (not (get-in root-conf [:modules module-name])) (do (print "Module " module-name " not found, aborting...") (os/exit 1)))
  (git/loud arch-dir "submodule" "deinit" "-f" (get-in root-conf [:modules module-name :path]))
  (sh/rm (path/join arch-dir ".git" "modules" (get-in root-conf [:modules module-name :path])))
  (module/rm arch-dir root-conf (first (res :default)))
  (print "module removed from index, if the module-data still exists please remove it now."))

(defn cli/modules/help [arch-dir root-conf]
  (print `Available Subcommands:
           add - add a new module
           ls - list modules
           rm - remove a module
           init - initialize an existing module
           deinit - deinitialize and existing module
           help - show this help`))

(defn cli/scripts [arch-dir root-conf]
  (error "not implemented yet")# TODO implement
  )

(defn cli/fsck [arch-dir root-conf]
  (os/execute ["git" "-C" arch-dir "fsck"] :p))

(defn cli/modules/execute [arch-dir root-conf name]
  # TODO also look up user scripts
  # TODO check if module is downloaded
  # if not show error message
  (git/async arch-dir "pull")
  (let [alias (get-in root-conf [:aliases name])
        module-name (if alias (alias :target) name)]
    (if (get-in root-conf [:modules module-name] nil)
        (do (def module-path (path/join arch-dir (get-in root-conf [:modules module-name :path])))
            (def prev-dir (os/cwd))
            (defer (os/cd prev-dir)
              (os/cd module-path)
              (os/execute [".main" ;(slice (dyn :args) 1 -1)]))
            (if ((git/changes arch-dir) name) # TODO this triggers for modified content and new commits -> only trigger on new commits
                (do (git/loud arch-dir "add" name) # TODO remove this auto commit once 
                    (git/loud arch-dir "commit" "-m" (string "updated " name))
                    (git/async arch-dir "push"))))
        (do (eprint "module does not exist, use help to list existing ones")
            (os/exit 1)))))

(defn cli/modules/init [arch-dir root-conf]
  (if (= (length (dyn :args)) 1) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-name ((dyn :args) 1))
  (if (not (get-in root-conf [:modules module-name])) (do (print "Module " module-name " not found, aborting...") (os/exit 1)))
  (git/loud arch-dir "submodule" "update" "--init" (get-in root-conf [:modules module-name :path])))

(defn cli/modules/deinit [arch-dir root-conf]
  (if (= (length (dyn :args)) 1) (do (print "Specify module to initialize by name, aborting...") (os/exit 1)))
  (def module-name ((dyn :args) 1))
  (if (not (get-in root-conf [:modules module-name])) (do (print "Module " module-name " not found, aborting...") (os/exit 1)))
  (git/loud arch-dir "submodule" "deinit" "-f" (get-in root-conf [:modules module-name :path]))
  (sh/rm (path/join arch-dir ".git" "modules" (get-in root-conf [:modules module-name :path]))))

(defn cli/modules [arch-dir root-conf]
  (if (<= (length (dyn :args)) 1)
      (do (cli/modules/ls arch-dir root-conf)
          (os/exit 0)))
  (def subcommand ((dyn :args) 1))
  (setdyn :args [((dyn :args) 0) ;(slice (dyn :args) 2 -1)])
  (case subcommand
    "add" (cli/modules/add arch-dir root-conf)
    "init" (cli/modules/init arch-dir root-conf)
    "deinit" (cli/modules/deinit arch-dir root-conf)
    "ls" (cli/modules/ls arch-dir root-conf)
    "rm" (cli/modules/rm arch-dir root-conf)
    "help" (cli/modules/help arch-dir root-conf)
    (cli/modules/execute arch-dir root-conf subcommand)))

(def default-root-conf {:modules []}) # TODO will no longer be needed in future

(defn print-root-help [arch-dir root-conf]
  (def preinstalled `Available Subcommands:
                      modules - manage your custom modules, use 'glyph module --help' for more information
                      alias - manage your aliases
                      git - execute git command on the arch repo
                      sync - sync the glyph archive
                      fsck - perform a filesystem check of arch repo
                      help - print this help`)
  (def custom @"")
  # TODO modify this to handle user scripts
  (if (root-conf :modules) (eachk k (root-conf :modules)
                                    (buffer/push custom "  " k " - " (get-in root-conf [:modules k :description]) "\n")))
  (if (= (length custom) 0)
    (print preinstalled)
    (do (prin (string preinstalled "\n" custom)) (flush))))

(defn main [&]
  (var root-conf @{})
  # TODO add config package to manage the config
  # TODO read myself and check if it matches any module or alias, if it does use it as first arg and proceed as normal
  # TODO add command to create symlinks for module or alias
  (def arch-dir (do (def env_arch_dir (os/getenv "GLYPH_ARCH_DIR"))
                    (def env_arch_stat (if env_arch_dir (os/stat env_arch_dir) nil))
                    (if (and env_arch_dir (= (env_arch_stat :mode) :directory))
                        env_arch_dir
                        (util/get-default-arch-dir))))
  (os/cd arch-dir)
  (let [root-conf-path (path/join arch-dir ".glyph" "config.jdn") # TODO don't auto write a glyph config add a command for it
        root-conf-stat (os/stat root-conf-path)]
        (if (or (not root-conf-stat) (not= (root-conf-stat :mode) :file))
            (do (set root-conf default-root-conf)
                (let [glyph-path (path/join arch-dir ".glyph")
                      glyph-stat (os/stat glyph-path)]
                     (if (not glyph-stat)
                         (os/mkdir glyph-path)))
                (spit root-conf-path root-conf)
                (git/slurp arch-dir "reset")
                (git/slurp arch-dir "add" ".glyph/config.jdn")
                (git/slurp arch-dir "commit" "-m" "glyph: initialized config"))
            (try (set root-conf (parse (slurp root-conf-path)))
                 ([err] (eprint "Could not load glyph config: " err)
                        (os/exit 1)))))
  # TODO never overwrite user config, not even in-memory
  # TODO wiki should be implemented as a module
  (put-in root-conf [:modules "wiki"] {:description "default wiki implementation" :path "wiki"}) # TODO add special handler here?
  (let [runtime-name (path/basename (first (dyn :args)))]
    (if ((merge (get root-conf :modules {}) (get root-conf :aliases {}))
         runtime-name)
        (do (array/insert (dyn :args) 0 "glyph")
            (put (dyn :args) 1 runtime-name))))
  (def subcommand (get (dyn :args) 1 nil))
  (array/remove (dyn :args) 1)
  (case subcommand
    # TODO add init command to write out default config
    "modules" (cli/modules arch-dir root-conf)
    "scripts" (cli/scripts arch-dir root-conf)
    "git" (os/exit (os/execute ["git" "-C" arch-dir ;(slice (dyn :args) 1 -1)] :p))
    "help" (print-root-help arch-dir root-conf)
    "--help" (print-root-help arch-dir root-conf)
    "-h" (print-root-help arch-dir root-conf)
    "" (print-root-help arch-dir root-conf)
    "sync" (sync {:arch-dir arch-dir})
    "fsck" (cli/fsck arch-dir root-conf) # TODO required?
    nil (print-root-help arch-dir root-conf)
    (cli/modules/execute arch-dir root-conf subcommand)))
