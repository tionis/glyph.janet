(declare-project
  :name "glyph"
  :description "a personal data manager for the command line"
  :dependencies  ["https://github.com/janet-lang/spork"
                  "https://tasadar.net/tionis/toolbox"
                  "https://tasadar.net/tionis/chronos" # TODO this needs various fixes and API changes (also replace this with toolbox)
                  ])

(declare-source :source ["glyph"])

(declare-executable
  :name "glyph"
  #:lflags ["-static"] # disable due to compile errors on platforms like termux on ARM
  :entry "glyph/cli.janet"
  :install true)

(declare-native
  :name "_uri"
  :source ["src/uri.c"])
