(import spork/base64)
(import spork/path)
(import spork/sh)
(import ./git)
(import ./glob)
(import ./util)
(import ./crypto)

######### TODO ###############################################################
# Add encryption                                                             #
#   Add node-id -> encryption-key mapping                                    #
# Add node management                                                        #
# Add signing                                                                #
# Rework trust architecture by leveraging trusted keys verified with git-skm #
##############################################################################

(defn- create_dirs_if_not_exists [dir]
  (let [meta (os/stat dir)]
    (if (not (and meta (= (meta :mode) :directory)))
      (sh/create-dirs dir))))

#(defn- get-key-from-glyph-store-kx [kx kx-public-key kx-secret-key]
#  (jhydro/kx/n2 (kx :kx) "this is a public pre-shared key!" kx-public-key kx-secret-key)

(defn- generic/set [base-dir key value &named recipients no-git commit-message ttl sign]
  # (var encryption-key @"")
  # (if recipients (set encryption-key (jhydro/secretbox/keygen)))
  # (defn gen-encryption-kx [recipient-public-key]
  #   (def packet @"")
  #   (def kx (jhydro/kx/n1 packet "this is a public pre-shared key!" recipient-public-key))
  #   (def key (jhydro/secretbox/encrypt encryption-key 0 "glyphekx" (kx :tx)))
  #   {:kx packet :key key})
  # (def kx (map gen-encryption-kx (if recipients recipients [])))
  # TODO add encryption (add recipient ids to :recipients as a map with their id as key and a kx buffer as the value)
  # get kx buffer by using the converting the recipient ids to public keys
  # TODO add signing (add source node id and sign whole encoded buffer, store signature in second line)
  # NOTE is signature needed if using git as commits are signed?
  (def formatted-key (path/join ;(path/posix/parts key)))
  (def path (path/join base-dir formatted-key))
  (def arch-dir (util/arch-dir))
  (def data @{:value value :ttl (if ttl (+ (os/time) ttl) nil)})
  (if (not value)
    (do
      (def path (path/join base-dir key))
      (default commit-message (string "store: deleted " key))
      (os/rm path)
      (unless no-git
        (git/loud arch-dir "reset")
        (git/loud arch-dir "add" "-f" path)
        (git/loud arch-dir "commit" "-m" commit-message)
        (git/async arch-dir "push")))
    (do
      (create_dirs_if_not_exists (path/join base-dir (path/dirname formatted-key)))
      (default commit-message (string "store: set " key " to " value))
      (def encoded-data (string/format "%j" data))
      (def to-write (buffer encoded-data))
      (when sign (buffer/push to-write "\n" (crypto/sign encoded-data)))
      (spit path to-write)
      (unless no-git
        (git/loud arch-dir "reset")
        (git/loud arch-dir "add" "-f" path)
        (git/loud arch-dir "commit" "-m" commit-message)
        (git/async arch-dir "push"))))
  value)

(defn- generic/get [base-dir key &named check-signature check-ttl commit-message no-git]
  # TODO allow specifying trusted keys in method signature
  (default check-signature true)  # TODO check signature
  # split at \n if more than 1 -> has signature
  # verify that line 1 :source matches signature
  (default check-ttl true)
  # TODO decrypt if needed
  (def path (path/join base-dir (path/join ;(path/posix/parts key))))
  (def stat (os/stat path))
  (if (or (= stat nil) (not (= (stat :mode) :file)))
    nil # Key does not exist
    (let [data (parse (slurp path))]
      (if (not (data :value)) (error (string "malformed store at " key))) # TODO handle this error better ()
      (if (and (data :ttl) (< (data :ttl) (os/time)))
        (do
          (generic/set base-dir key nil :no-git no-git :commit-message (if commit-message commit-message (string "store: expired " key)))
          nil)
        (data :value)))))

(defn- generic/ls [base-dir &opt glob-pattern]
  (default glob-pattern ".")
  (create_dirs_if_not_exists base-dir)
  (def ret @[])
  (def prev (os/cwd))
  (os/cd base-dir)
  (if (or (string/find "*" glob-pattern)
          (string/find "?" glob-pattern))
    (let [pattern (glob/glob-to-peg glob-pattern)]
         (sh/scan-directory "." |(if (and (= ((os/stat $0) :mode) :file)
                                          (peg/match pattern $0))
                                     (array/push ret $0))))
    (let [glob-stat (os/stat glob-pattern)]
      (if (and glob-stat (= (glob-stat :mode) :directory))
          (do (sh/scan-directory glob-pattern |(if (= ((os/stat $0) :mode) :file) (array/push ret $0))))
          @[])))
  (os/cd prev)
  ret)

(defn- generic/ls-contents [base-dir glob-pattern &named no-git commit-message]
  (def ret @{})
  (each item (generic/ls base-dir glob-pattern)
    (put ret item (generic/get base-dir item :no-git no-git :commit-message commit-message)))
  ret)

(defn- get-cache-dir [] (path/join (util/arch-dir) ".git/glyph/cache"))
(defn cache/get [key] (generic/get (get-cache-dir) key :no-git true :check-signature false))
(defn cache/set
  "Set key to value in cache, with optional ttl (time-to-live in seconds) and encryption (not working yet, will use node's keys)"
  [key value &named ttl encrypt]
  (if encrypt
    (generic/set (get-cache-dir) key value :no-git true :ttl ttl :recipients [(crypto/my-id)])
    (generic/set (get-cache-dir) key value :no-git true :ttl ttl)))
(defn cache/ls [&opt glob-pattern] (generic/ls (get-cache-dir) glob-pattern))
(defn cache/rm [key] (cache/set key nil) :no-git true)
(defn cache/ls-contents [glob-pattern] (generic/ls-contents (get-cache-dir) glob-pattern :no-git true))

(defn- get-config-dir [] (path/join (util/arch-dir) "config"))
(defn store/get [key &named commit-message] (generic/get (get-config-dir) key :commit-message commit-message))
(defn store/set [key value &named commit-message ttl recipients]
  (generic/set (get-config-dir)
               key value
               :commit-message commit-message
               :ttl ttl
               # TODO enable this when ready:  :signing-key (let [key (cache/get "node/sign/secret-key")] (if key key (error "no signing key configured, cannot sign value for store")))
               # TODO :recipients (map recipient-signing-key-to-kx-public-key recipients)
               ))
(defn store/ls [&opt glob-pattern] (generic/ls (get-config-dir) glob-pattern))
(defn store/rm [key &named commit-message] (store/set key nil :commit-message commit-message))
(defn store/ls-contents [glob-pattern &named commit-message] (generic/ls-contents (get-config-dir) glob-pattern :commit-message commit-message))
