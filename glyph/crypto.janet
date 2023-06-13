(import spork/randgen)
(import spork/path)
(import spork/sh)

(defn sh/home []
  (case (os/which)
    :linux (os/getenv "HOME")
    (error "os not supported yet")))

(defn sh/tempfile []
  (path/join "/tmp" (string "glyph-" (math/floor (* (randgen/rand-uniform) 10000000000)))))

(defn get-tmp-dir [] # TODO replace this horrible hack
  (def p (path/join "/tmp" (string/format "%j" (math/floor (* (randgen/rand-uniform) 10000000000)))))
  (os/mkdir p)
  p)

(defn get-key-path []
  (if (os/getenv "SSH_AUTH_SOCK")
    (let [tmp-path (sh/tempfile)
          key (first (string/split "\n" (sh/exec-slurp "ssh-add" "-L")))]
      (unless key (error "could not get key from ssh"))
      (spit tmp-path key)
      tmp-path)
    (path/join (sh/home) ".ssh" "id_ed25519"))) # Default to id_ed25519 keys (maybe cycle through available ones)

(defn get-pub-keys []
  (if (os/getenv "SSH_AUTH_SOCK")
    (string/split "\n" (sh/exec-slurp "ssh-add" "-L"))
    [(slurp (path/join (sh/home) ".ssh" "id_ed25519"))])) # Default to id_ed25519 keys (maybe cycle through available ones)

(defn my-id []
  (string/join (slice (string/split " " (first (get-pub-keys))) 0 2) " "))

(defn split-into-segments [str len]
  (def str-len (length str))
  (def arr @[])
  (loop [i :range [0 (dec (/ str-len len))]]
    (def cur-ind (* i len))
    (array/push arr (slice str cur-ind (+ cur-ind len))))
  (def rest (% str-len len))
  (if (> rest 0) (array/push arr (slice str (- str-len rest) -1)))
  arr)

(defn ssh-sig-extract-key [buf]
  (string/join
    (peg/match
      ~{:line (* (capture (* (not "-----END SSH SIGNATURE-----") (to "\n"))) "\n")
        :main (* "-----BEGIN SSH SIGNATURE-----\n" (some :line) "-----END SSH SIGNATURE-----\n")}
      buf)))

(defn ssh-sig-encode
  "Just encodes the key in the same format that ssh-keygen outputs"
  [key]
  (string
    (string/join ["-----BEGIN SSH SIGNATURE-----"
                  ;(split-into-segments key 70)
                  "-----END SSH SIGNATURE-----"]
                 "\n") "\n"))

(defn sign [data &named namespace]
  (default namespace "glyph")
  (def key-path (get-key-path))
  (def proc (os/spawn ["ssh-keygen" "-Y" "sign" "-f" key-path "-n" namespace] :px {:in :pipe :out :pipe :err :pipe}))
  (def buf @"")
  (ev/gather
    (do (:write (proc :in) data) (:close (proc :in)))
    (:read (proc :out) :all buf)
    (:wait proc))
  (ssh-sig-extract-key buf))

(defn verify [data signature allowed-signers &named namespace]
  (default namespace "glyph")
  (default allowed-signers (get-pub-keys))
  (def key-path (get-key-path))
  (def allowed-signers-str
    (string/join
      (map (fn [key]
             (def key-arr (string/split " " key))
             (string (get key-arr 2 "some-id") " "
                     (key-arr 0) " " (key-arr 1)))
           allowed-signers)
      "\n"))
  (def tmp-dir (get-tmp-dir))
  (def allowed-signers-file (path/join tmp-dir "allowed_signers"))
  (spit allowed-signers-file allowed-signers-str)
  (def signature-file (path/join tmp-dir "signature"))
  (spit signature-file (ssh-sig-encode signature))
  (spit (path/join tmp-dir "commit") data)
  (def principal
    (sh/exec-slurp "ssh-keygen" "-Y" "find-principals" "-s" signature-file "-f" allowed-signers-file))
  (def proc (os/spawn ["ssh-keygen"
                       "-Y" "verify"
                       "-f" allowed-signers-file
                       "-n" namespace
                       "-s" signature-file
                       "-I" principal] :p {:in :pipe :out :pipe}))
  (ev/gather
    (do (:write (proc :in) data) (:close (proc :in)))
    (:wait proc))
  (if (not= (proc :return-code) 0)
    (error "could not verify commit signature"))
  true)
