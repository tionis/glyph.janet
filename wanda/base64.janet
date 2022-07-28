(defn array-pad-right
  [xs size padder]
  "Fills and returns an array with `padder` until it reaches `size`. Returns array as is if it's already at or over the given size."
  (let [l (length xs)]
    (if (< l size)
      (do (for i l size
            (put xs i padder))
          xs)
      xs)))

(defn array-pad-left
  [xs size padder]
  "Fills and returns an array with `padder` at the start until it reaches `size`. Returns array as is if it's already at or over the given size."
  (let [l (length xs)]
    (if (< l size)
      (do (for i 0 (- size l)
            (array/insert xs i padder))
          xs)
      xs)))

(defn reverse-array [xs]
      (let [l (length xs)
            new-arr (array/new l)]
        (for i 0 l
          (put new-arr i (get xs (- (dec l) i))))
        new-arr))

(defn decimal->binary
  [x &opt bin]
  "Converts a binary number into its binary representation of an array of bits."
  (default bin @[])
    (if (< x 1)
        (reverse-array bin)
        (let [rem (% x 2)
            new-x (math/floor (/ x 2))]
            (decimal->binary new-x (array/push bin rem)))))

(defn binary->decimal
  [xs]
  "Converts an array of bits into a single decimal number."
  (var num 0)
  (for i 0 (length xs)
    (when (= 1 (get (reverse-array xs) i))
      (set num (+ num (math/pow 2 i)))))
  num)

(defn tuple->array [xs]
  (let [size (length xs)]
    (array/concat (array/new size) xs)))

(def b64/table "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defn octets->sextets
  [octets]
  "Converts a list of size-8 arrays (octets) to a list of size-6 arrays (sextets). The last sextet may not be filled."
  (->> octets
       flatten
       (partition 6)
       (map tuple->array)))

(defn sextets->octets
  [octets]
  "Converts a list of size-6 arrays (sextets) to a list of size-8 arrays (octets). The last octet may not be filled."
  (->> octets
      flatten
      (partition 8)))

(defn char->b64-idx [c] (index-of c b64/table))

(defn quadruples->bytes [xs]
  (let [sextets (map |(-> $0
                         char->b64-idx
                         decimal->binary
                         (array-pad-left 6 0)) xs)
        octets (sextets->octets sextets)]
    (apply string/from-bytes (map binary->decimal octets))))

(defn byte->binary [c]
  (-> c decimal->binary (array-pad-left 8 0)))

(defn pad-last-sextet [xs]
  (let [last-index (dec (length xs))]
    (update xs last-index array-pad-right 6 0)))

(defn add-padding [s]
  (if (zero? (% (length s) 4))
      s
      (let [pad-count (- 4 (% (length s) 4))]
        (string s (string/repeat "=" pad-count)))))

(defn encode
  [s]
  "Converts a string of any format (UTF-8, binary, ..) to base64 encoding."
  (let [octets (map byte->binary (string/bytes s))
        sextets (pad-last-sextet (octets->sextets octets))
        bytes (map binary->decimal sextets)
        b64-bytes (map (fn [i] (get b64/table i)) bytes)
        b64 (add-padding (apply string/from-bytes b64-bytes))]
    b64))

(defn decode
  [s]
  "Converts a base64 encoded string to its binary representation of any format (UTF-8, binary, ..)."
  (let [without-padding (peg/replace-all "=" "" s)
        padded? (not (zero? (% (length without-padding) 4)))
        quadruples (partition 4 without-padding)
        bytes (map quadruples->bytes quadruples)
        b64 (apply string bytes)]
    (if padded? (slice b64 0 -2) b64)))
