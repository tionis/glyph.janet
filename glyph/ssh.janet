(import spork/sh)
(use ./store)

(def- ssh-agent-output-grammar
  (peg/compile
    ~{:main (some (* :line (+ "\n" -1)))
      :line (+ :ssh-auth-sock :ssh-agent-pid :rest)
      :ssh-auth-sock (replace (* "setenv SSH_AUTH_SOCK " (capture (to ";")) ";")
                              ,|["SSH_AUTH_SOCK" $0])
      :ssh-agent-pid (replace (* "setenv SSH_AGENT_PID " (capture (to ";")) ";")
                              ,|["SSH_AGENT_PID" $0])
      :rest (to (+ "\n" -1))}))

(defn- set-env-vars [agent-conn-info]
  (os/setenv "SSH_AUTH_SOCK" (agent-conn-info "SSH_AUTH_SOCK"))
  (let [agent-pid (agent-conn-info "SSH_AGENT_PID")]
    (if agent-pid (os/setenv "SSH_AGENT_PID" agent-pid))))

(defn agent/start
  "starts glyph's ssh-agent if no agent is reachable"
  []
  (def devnull {:out (sh/devnull) :err (sh/devnull)})
  # TODO add timeout of around 0.3s to all ssh-add -l checks to speed up detection of hanging ssh-agent connections
  (when (= (os/execute ["ssh-add" "-l"] :p devnull) 2)
    # Could not open a connection to your authentication agent.
    # Load stored agent connection info.
    (var agent-conn-info (cache/get "node/ssh/ssh-agent/connection-info"))
    (if agent-conn-info (set-env-vars agent-conn-info))

    (when (or (not agent-conn-info) (= (os/execute ["ssh-add" "-l"] :p devnull) 2))
      # Start agent and store agent connection info.
      (set agent-conn-info (from-pairs (peg/match ssh-agent-output-grammar (sh/exec-slurp "ssh-agent" "-c"))))
      (cache/set "node/ssh/ssh-agent/connection-info" agent-conn-info)
      (set-env-vars agent-conn-info)
    ))

  # Load identities
  (when (= (os/execute ["ssh-add" "-l"] :p devnull) 1)
    # The agent has no identities, add one
    # Can add further key adding options like key timeout (e.g. -t 2h) below
    (os/execute ["ssh-add"] :p devnull)))
