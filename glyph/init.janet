#!/bin/env janet
(import spork :prefix "")
(import jhydro :export true)
(import ./glob :export true)
(import ./util :export true)
(import ./git :export true)
(import ./store :prefix "" :export true)
(import ./collections :prefix "" :export true)
(import ./sync :prefix "" :export true)
(import ./scripts :export true)
(import ./daemon :export true)
(import ./ssh :export true)

(defn init-env
  "initialize glyphs environment"
  []
  (ssh/agent/start))

### Legacy Support ###
(defn modules/execute [name args] (collections/execute name args))

(defn gen_keys []
  (let [sign_keys (jhydro/sign/keygen)
        kx_keys (jhydro/kx/keygen)]
        (cache/set "node/sign/secret-key" (sign_keys :secret-key))
        (cache/set "node/sign/public-key" (sign_keys :public-key))
        (cache/set "node/kx/secret-key" (kx_keys :secret-key))
        (cache/set "node/kx/public-key" (kx_keys :public-key))))

# TODO add generic sign and verify function?

(defn add-sign-key [pubkey]
  # TODO add signing key to config store and sign it with itself
  #(def key (base64/encode (jhydro/hash/hash 32 pubkey "gnodekey")))
  #(config/set (string "glyph/nodes/" key) pubkey)
  )

(defn add-kx-key [pubkey]
  # TODO add kx key to config store and sign it with own key
  )

(defn id [] (slice (base64/encode (jhydro/hash/hash 16 (cache/get "node/sign/public-key") "gnodekey")) 0 8))

(defn init-keys []
  (when (not (cache/get "node/sign/secret-key"))
    (let [sign-keys (jhydro/sign/keygen)
          kx-keys (jhydro/kx/keygen)]
      (cache/set "node/sign/secret-key" (sign-keys :secret-key))
      (cache/set "node/sign/public-key" (sign-keys :public-key))
      (cache/set "node/kx/secret-key" (kx-keys :secret-key))
      (cache/set "node/kx/public-key" (kx-keys :public-key))
      (add-sign-key (sign-keys :public-key))
      (add-kx-key (kx-keys :public-key))))
  (when (not (cache/get "node/kx/secret-key"))
    (let [kx-keys (jhydro/kx/keygen)]
      (cache/set "node/kx/secret-key" (kx-keys :secret-key))
      (cache/set "node/kx/public-key" (kx-keys :public-key))
      (add-kx-key (kx-keys :public-key)))))

(defn fsck []
  (def arch-dir (util/arch-dir))
  (print "Starting normal recursive git fsck...")
  (git/fsck arch-dir)
  (print)
  (collections/fsck))
