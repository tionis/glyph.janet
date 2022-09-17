(use spork)
(use sh)

(def- sh/grammar ~{
  :ws (set " \t\r\n")
  :escape (* "\\" (capture 1))
  :dq-string (accumulate (* "\"" (any (+ :escape (if-not "\"" (capture 1)))) "\""))
  :sq-string (accumulate (* "'" (any (if-not "'" (capture 1))) "'"))
  :token-char (+ :escape (* (not :ws) (capture 1)))
  :token (accumulate (some :token-char))
  :value (* (any (+ :ws)) (+ :dq-string :sq-string :token) (any :ws))
  :main (any :value)
})

(def- sh/peg (peg/compile sh/grammar))

(defn sh/split
  "Split a string into 'sh like' tokens, returns
   nil if unable to parse the string."
  [s]
  (peg/match sh/peg s))

(defn- sh/quote1
  [arg]
  (def buf (buffer/new (* (length arg) 2)))
  (buffer/push-string buf "'")
  (each c arg
    (if (= c (chr "'"))
      (buffer/push-string buf "'\\''")
      (buffer/push-byte buf c)))
  (buffer/push-string buf "'")
  (string buf))

(defn sh/quote
  [& args]
  (string/join (map sh/quote1 args) " "))

(while true
  (prin "> ")(flush) # TODO add built-ins like cd
  (eval (let [input ((getline/make-getline))]
          (if (= (length input) 0) (os/exit 1))
          (if (index-of (input 0) [40 91 123 40]) # Use PEG to check if is valid janet 
              (parse input)
              ~($* (sh/split ,input))))))
