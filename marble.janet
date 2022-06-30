(defn assert-dictionary
  `Asserts that provided data is dictionary`
  [t data]
  (assert
    (dictionary? data)
    (string t " must be dictionary")))

(defn assert-indexed
  `Asserts that provided data is indexed collection`
  [t data]
  (assert
    (indexed? data)
    (string t " must be indexed")))

(defn map-keys
  ```
  Returns new table with function `f` applied to `data`'s
  keys recursively.
  ```
  [f data]
  (assert-dictionary "Data" data)
  (-> (seq [[k v] :pairs data]
        [(f k) (if (dictionary? v) (map-keys f v) v)])
      flatten
      splice
      table))

(defn map-vals
  ```
  Returns new table with function `f` applied to `data`'s values.
  ```
  [f data]
  (assert-dictionary "Data" data)
  (def res @{})
  (loop [[k v] :pairs data] (put res k (f v)))
  res)

(defn select-keys
  ```
  Returns new table with selected `keyz` from dictionary `data`.
  ```
  [data keyz]
  (assert-dictionary "Data" data)
  (assert-indexed "Keys" keyz)
  (def res @{})
  (loop [[k v] :pairs data
         :when (some |(= k $) keyz)] (put res k v))
  res)

(defmacro cond->
  ```
  Threading conditional macro. It takes `val` to mutate,
  and `clauses` pairs of with condition and operation to which the `val`,
  is put as first argument. All conditions are tried and
  for truthy conditions the operation is ran.
  Returns mutated value if any condition is truthy.
  ```
  [val & clauses]
  (with-syms [res]
    ~(do
       (var ,res ,val)
       ,;(map
           (fn [[cnd ope]]
             (def ope (if (tuple? ope) ope (tuple ope)))
             (tuple
               'if cnd
               (tuple 'set res
                      (tuple (first ope) res
                             ;(tuple/slice ope 1 -1)))))
           (partition 2 clauses))
       ,res)))

(defmacro cond->>
  ```
  Threading conditional macro. It takes `val` to mutate,
  and `clauses` pairs of condition and operation to which the `val`,
  is put as last argument. All conditions are tried and
  for truthy the operation is ran.
  Returns mutated value if any condition is truthy.
  ```
  [val & clauses]
  (with-syms [res]
    ~(do
       (var ,res ,val)
       ,;(map
           (fn [[cnd ope]]
             (def ope (if (tuple? ope) ope (tuple ope)))
             (tuple
               'if cnd
               (tuple 'set res (tuple ;ope res))))
           (partition 2 clauses))
       ,res)))

(defn make
  ```
  Creates new table from a variadic `table-pairs`
  arguments and sets its prototype to `prototype`.
  Factory function for creating new objects from prototypes.
  ```
  [prototype & table-pairs]
  (def object
    (if-let [t (and (one? (length table-pairs))
                    (table? (def _t (in table-pairs 0)))
                    _t)]
      t (table ;table-pairs)))
  (table/setproto object prototype))

(defmacro capout
  `Captures the standart output.`
  [& body]
  (with-syms [o]
    ~(do
       (def ,o @"")
       (with-dyns [:out ,o] ,;body)
       ,o)))

(defmacro caperr [& body]
  ```
  Captures the error output of the variadic `body`.
  ```
  (with-syms [o]
    ~(do
       (def ,o @"")
       (with-dyns [:err ,o] ,;body)
       ,o)))

(defn one-of
  ```
  Takes value `v` and variadic number of values in `ds`,
  and returns the `v` if it is present in the `ds`.
  ```
  [v & ds]
  (find |(= v $) ds))

(defmacro match-first [p s]
  {:deprecated :normal}
  ```
  Returns first match in string `s` by the peg `p`.
  ```
  [p s]
  ~(first (peg/match ,p ,s)))

(defmacro first-capture
  `Returns first match in string s by the peg p`
  [p s]
  ~(first (peg/match ,p ,s)))

(defmacro fprotect
  ```
  Evaluate expressions `body`, while capturing any errors. Evaluates to a tuple
  of two elements. The first element is true if successful, false if an
  error. The second is the return value or the fiber that errored respectively.
  Use it, when you want to get the stacktrace of the error.
  ```
  [& body]
  (with-syms [f r e]
    ~(let [,f (,fiber/new (fn [] ,;body) :ie)
           ,r (,resume ,f)
           ,e (,= :error (,fiber/status ,f))]
       [(,not ,e) (if ,e ,f ,r)])))

(defn union
  `Returns the union of the the members of the sets.`
  [& sets]
  (def head (first sets))
  (def ss (array ;sets))
  (while (not= 1 (length ss))
    (let [aset (array/pop ss)]
      (each i aset
        (if-not (find-index |(= i $) head) (array/push head i)))))
  (first ss))

(defn intersect
  `Returns the intersection of the the members of the sets.`
  [& sets]
  (def ss (array ;sets))
  (while (not= 1 (length ss))
    (let [head (first ss)
          aset (array/pop ss)]
      (put ss 0 (filter (fn [i] (find-index |(deep= i $) aset)) head))))
  (first ss))

(def peg-grammar
  ```
  Custom peg grammar with crlf and to end.
  ```
  (merge (dyn :peg-grammar)
         ~{:crlf "\r\n"
           :to-crlf (* '(to :crlf) :crlf)
           :toe '(to -1)}))

(defn named-capture
  ```
  Creates group where the first member is keyword `name`
  and other members are `captures`.
  ```
  [name & captures]
  ~(group (* (constant ,(keyword name)) ,;captures)))

(def <-: named-capture)

(def .
  ```
  Alias for `string`
  ```
  string)

(defmacro get-only-el
  ```
  Convenience macro for geting first element
  from first row of the two dimensional array `m`.
  ```
  [m]
  ~(in (in ,m 0) 0))

(defmacro do-var
  ```
  Convenience macro for defining varible
  named `v` with value `d` before `body`
  and returning it after evaluating
  expresions, that presumably modify
  `v`, in the `body`.
  ```
  [v d & body]
  ~(do (var ,v ,d) ,;body ,v))

(defmacro vars
  ```
  Defines many variables as in let `bindings`.
  ```
  [& bindings]
  ~(upscope
     ,;(seq [[n v] :in (partition 2 bindings)] (tuple 'var n v))))

(defmacro defs
  ```
  Defines many constants as in let `bindings`.
  ```
  [& bindings]
  ~(upscope
     ,;(seq [[n v] :in (partition 2 bindings)] (tuple 'def n v))))
