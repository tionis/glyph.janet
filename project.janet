(declare-project
  :name "wiki.janet" # required
  :description "dotfile managment" # some example metadata.
  #:lflags ["-static"]
  # Optional urls to git repositories that contain required artifacts.
  :dependencies  ["https://git.sr.ht/~pepe/jff.git"
                  "https://github.com/janet-lang/spork"])

(declare-source
  # :source is an array or tuple that can contain
  # source files and directories that will be installed.
  # Often will just be a single file or single directory.
  :source ["wiki.janet"
           "dateparser.janet"
           "date.janet"
           "filesystem.janet"])

#(declare-native
  # :name "mynative"
  # :source ["mynative.c" "mysupport.c"]
  # :embedded ["extra-functions.janet"])

(declare-executable
  :name "wiki"
  :entry "wiki.janet"
  :install true)
