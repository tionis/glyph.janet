(declare-project
  :name "wiki"
  :description "wiki/knowledgebase managment program"
  #:lflags ["-static"]
  :dependencies  ["https://git.sr.ht/~pepe/jff.git"
                  "https://github.com/janet-lang/spork"])

(declare-source :source ["wiki"])

#(declare-native
  # :name "mynative"
  # :source ["mynative.c" "mysupport.c"]
  # :embedded ["extra-functions.janet"])

(declare-executable
  :name "wiki"
  :entry "wiki/init.janet"
  :install true)
