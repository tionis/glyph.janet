# A glob module that works by compiling globs to janet pegs.

(def glob-grammar
  ~{:main (sequence (any :rule) -1)
    :rule (sequence (choice
                      (sequence "***" (error (constant "invalid glob pattern")))
                      (sequence "**" (error (constant "** not supported")))
                      :1star
                      :qmark
                      :lit))
    :qmark (sequence "?" (constant 1))
    :1star
    (choice
      (sequence "*" -1 (constant (any 1)))
      (cmt (sequence "*" :lit) ,(fn [lit] ~(sequence (any (sequence (not ,lit) 1)) ,lit))))
    :lit (capture (some (sequence (not (set "*?")) 1)))})

(def glob-parser
  (peg/compile glob-grammar))

(defn glob-to-peg
  [glob]
  ~{:main (sequence ,;(peg/match glob-parser glob) -1)})

(defn matches*
  "function version of matches supporting dynamic globs"
  [glob to-match]
  (truthy? (peg/match (glob-to-peg glob) to-match)))

(defmacro matches
  "precompile glob and perform "
  [glob to-match]
  (unless (string? glob)
    (error "use glob/matches* when glob is not a string literal"))
  (def compiled-peg (peg/compile (glob-to-peg glob)))
  ~(,truthy? (,peg/match ,compiled-peg ,to-match)))
