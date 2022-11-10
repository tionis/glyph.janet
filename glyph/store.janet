(defn cache/get [key])
(defn cache/set [key value &named ttl])
(defn cache/ls [pattern])

(defn store/get [key])
(defn store/set [key value grous])
(defn store/ls [pattern])

(defmacro cache/exec)
