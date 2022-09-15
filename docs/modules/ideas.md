# Ideas for future Modules
Here are some Ideas for modules to implement:

- Games - A game library, which allows one to decide for each game wether to download it (each game is its own git repo with lfs)
- Music - A music library, which allows one to decode which songs to download (no idea yet how to implement)
- Documents - Documents are implemented by just using recursing submodules with lfs enabled. An UI to decide which ones to download remains to be implemented
- Videos - recursing submodules
- Pictures - recusing submodules
- Books - libraries implemented as recursing submodules (not sure if recursion is needed here)
- dev - recursing submodules with following added features: automatic git-sync-changes (add shell wrapper for this)

## Notes on Implementation
While modules can be implemented using any scripting language (or even binary executable) the "happy path" is meant to be a janet script.  
The Idea would be to expose a few helpful functions in the Glyph janet API so that simple Modules like the Documents one are just a few lines of code that mainly import from glyph.  
For this to work following externally exposed functionalities are needed:
- Generic UI to select which submodules to download (maybe use jff with multi select for this (multi-select remains to be implemented))
- Maybe a janet implementation of git-sync-changes
