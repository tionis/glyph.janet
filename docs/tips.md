# Tips
## Module shortcuts
If you want to use modules without invoking glyph before them (`wiki $some_path` instead of `glyph wiki $some_path`), you can use a script looking like the one below somewhere along your '$PATH':
```janet
#!/bin/env janet
(use glyph/cli)
(defn main [_ & args] (modules/execute "wiki" args))
```
