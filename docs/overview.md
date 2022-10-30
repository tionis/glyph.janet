# Overview
Glyph uses a parent git repo, called the arch repo, which is the root of your personal data archive.
This arch repo, can have multiple glyph modules (currently implemented as git submodules) that implement additional functionality.  
These modules can be added, removed and executed using the modules subcommand. To execute a module it needs an executable file at the $root-of-module/.main. All arguments passed to glyph after the module selection are passed to this executable.  
In practice this means each module defines it's own code in the .main file and can be used without glyph by executing it while having the current working directory in the root of the module. Several example .main files can be found in the examples directory of the glyph source repository.
Each module can also specify which special commands it supportes in a .main.info.json file with the key "supported" specifying an map of keys that match a module feature and values that specify which subcommand needs to be invoked to trigger them. (this feature is not yet implemented as the module standard is not yet finished).

TODO: extend this documentation
