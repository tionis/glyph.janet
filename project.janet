  :name "glyph"
(declare-project
  :description "a personal data manager for the command line"
  :dependencies  ["https://github.com/janet-lang/spork"
                  "https://git.sr.ht/~pepe/jfzy" # TODO this can probably be removed, but is still required by jff as a transitive dependency
                  "https://tasadar.net/tionis/jeff.git" # TODO this needs UI improvements
                  "https://github.com/tionis/remarkable" # TODO this needs tags support
                  "https://tasadar.net/tionis/chronos" # TODO this needs various fixes and API changes
                  ])

(declare-source :source ["glyph"])

(declare-executable
  :name "glyph"
  :lflags ["-static"]
  :entry "glyph/cli.janet"
  :install true)
