# Modules Standard
> Warning: this standard is not finalized and still in flux, as such supported commands and other details might change in the future

## Supported Commands
- fsck - execute a file integrity check for module 
- setup - executed after the module was initialized to setup for a new device
- bundle - functions similar to git bundle to pack a module into a file that contains all ists data
- sync - synchronizes module with upstream (no longer needed, git's recursive submodule update should handle this now)
- show $some-path - similar to git show, print requested file version to stdout
