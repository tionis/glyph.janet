# Termux
To use glyph in termux several things have to be noted:  
These caveats apply if you want to initialize a collection in Androids shared storage:  
- use 'git config --global --add safe.directory "$DIR_YOU_WANT_A_COLLECTION_IN"' before initializing the collections
- after collection init use 'git config core.fileMode false' to ignore file mode changes
- the .main script won't work as normal [a workaround is tracked here](https://tasadar.net/tionis/glyph/issues/69)
- ignoring the fileMode might also be required in submodules
