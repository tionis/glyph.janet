(declare-project
  :name "glyph"
  :description "a personal data manager for the command line"
  #:lflags ["-static"]
  :dependencies  ["https://git.sr.ht/~pepe/jfzy" # TODO this can probably be removed, but is still required by jff
                  "https://tasadar.net/tionis/fuzzy-select.git" # TODO this needs UI improvements # TODO switch back to pepes version if changes are merged
                  "https://github.com/janet-lang/spork"
                  "https://github.com/tionis/remarkable" # TODO this needs tags support (could just use markable and then parse the html back to DSL)
                  "https://tasadar.net/tionis/chronos" # TODO this needs various fixes and API changes
                  "https://github.com/janet-lang/jhydro" # TODO this may be removed
                  "https://github.com/andrewchambers/janet-flock"
                  #"https://github.com/janet-lang/sqlite3"
                  "https://github.com/andrewchambers/janet-uri"]) # TODO replace this with a peg based uri parser

(declare-source :source ["glyph"])

#(declare-native
  # :name "some-lib"
  # :source ["some-lib.c"])

(declare-executable
  :name "glyph"
  :entry "glyph/init.janet"
  :install true)
