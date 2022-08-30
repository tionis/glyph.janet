(declare-project
  :name "wanda"
  :description "wiki/knowledgebase managment program"
  #:lflags ["-static"]
  :dependencies  ["https://git.sr.ht/~pepe/jfzy" # TODO this can probably be removed, but is still required by jff
                  "https://git.sr.ht/~pepe/jff.git" # TODO this needs UI improvements
                  "https://github.com/janet-lang/spork"
                  "https://github.com/tionis/remarkable" # TODO this needs tags support
                  "https://tasadar.net/tionis/chronos" # TODO this needs various fixes and API changes
                  "https://github.com/janet-lang/jhydro" # TODO this may be removed
                  #"https://github.com/janet-lang/sqlite3"
                  "https://github.com/andrewchambers/janet-uri"]) # TODO replace this with a peg based uri parser

(declare-source :source ["wanda"])

#(declare-native
  # :name "some-lib"
  # :source ["some-lib.c"])

(declare-executable
  :name "wanda"
  :entry "wanda/init.janet"
  :install true)
