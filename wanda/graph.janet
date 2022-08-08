(import spork/json)

(defn json
  "get json encoding of graph"
  [adj]
  (json/encode adj))

(defn dot
  "get dot encoding of graph"
  [adj]
  (var ret @"digraph wiki {\n")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "  \"" k "\"\n")
      (buffer/push ret "  \"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  (buffer/push ret "}"))

(defn blockdiag
  "get blockdiag encoding of graph"
  [adj]
  (var ret @"")
  (eachk k adj
    (if (= (length (adj k)) 0)
      (buffer/push ret "\"" k "\"\n")
      (buffer/push ret "\"" k "\" -> \"" (string/join (adj k) "\", \"") "\"\n")))
  ret)

(defn mermaid
  "get mermaid encoding of graph"
  [adj]
  (var ret @"graph TD\n")
  (def id @{})
  (var num 0)
  (eachk k adj
    (put id k num)
    (+= num 1))
  (eachk k adj
    (if (= (length (adj k)) 0)
        (buffer/push ret "  " (id k) "[" k "]\n"))
    (each l (adj k)
      (buffer/push ret "  " (id k) "[" k "] --> " (id l) "\n")))
  ret)
