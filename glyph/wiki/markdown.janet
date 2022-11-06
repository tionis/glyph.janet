(import remarkable)

(defn parse-md [input &opt your-blocks your-inlines your-functions your-priorities]
  (remarkable/parse-md input your-blocks your-inlines your-functions your-priorities))

(defn render-html [node &opt opts]
  (remarkable/render-html node opts))

(defn walk-and-return-entity-x [dsl x]
  (if (= (type dsl) :tuple)
      (if (> (length dsl) 1)
          (if (= (dsl 0) x)
              @[dsl]
              (if (or ((dsl 1) :container?) ((dsl 1) :inlines?))
                  (do (def ret @[])
                      (each item (dsl 2)
                        (each found-item (walk-and-return-entity-x item x)
                          (array/push ret found-item)))
                      ret)
                  @[]))
          @[])
      @[]))

(defn extract-all-of-entity-x [str x]
  (walk-and-return-entity-x (parse-md (string/trim str)) x))

(defn get-links [str]
  (def ret @[])
  (each link (extract-all-of-entity-x str :link)
    (array/push ret {:name (string (first (link 2))) :target ((link 1) :url)}))
  ret)
