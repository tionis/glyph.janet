(import remarkable)

(defn extract-all-of-entity-x [str x]
  (def parsed (remarkable/parse-md str))
  (def ret @[])
  # write this whole thing recursive depth first
  # go into current element, check if is container, if true go one deeper, if false
  # check if is paragraph?
  )

(defn get-links [str]
  (def ret @[])
  (each link (extract-all-of-entity-x str :link)
    (array/push {:name (link 2) :target ((link 1) :url)}))
  ret)
