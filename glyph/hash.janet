(import ./base64)
(import jhydro)

(defn dir/simple
  "Very simple hashing algorithm that just hashes the names of the children of dir.
  Useful for simple and fast checking if elements of directory have changed. (Without recursion)"
  [dir]
  (base64/encode (jhydro/hash/hash 16 (string/join (os/dir dir)) "=status=")))
