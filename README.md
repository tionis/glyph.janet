# Wanda
> NOTICE: This tool is actually in the process to be reworked completly.  

In the future the wiki will be one of multiple (optional) modules including:  
- config managment
- device crypto-key managment
- the wiki itself
- timers
- many more
This will make wanda (may be renamed) just a simple personal archive manager, that is defined by a git repo that defines it's modules

## Old Description (still mostly relevant)
Wanda (**W**iki **AND** **A**rchive) is a knowledgebase helper that help you to manage a personal wiki and also manage an archive of other data.  
The Wiki part of this application is kind of a commandline equivalent of Obsidian or can also be seen as a wrapper for other wiki helpers like vimwiki and uses git for syncing of different machines as well as versioning of the documents.  
For the Archive part of this application it adds a few wrappers for downloading and managing data (extendable by user scripts) as well as a way to synchronize the data alongside the wiki without checking them directly into git. (Not yet implemented).
Large parts of wanda are self documenting via the cli and --help flags, following things should be noted:  
- Wanda discoveres the git repo it should work on first by looking up the `WANDA_ARCH_DIR` environment variable and defaults to `$HOME/arch` if not

If anyone relies on this tool, please inform me over [any communication channel](https://tionis.dev) (including github issues) so that I don't push a change to crashes your workflow.

At the moment the program incorporates code from other projects that I want to attribute below:
- [Spork](https://github.com/janet-lang/spork)
- [Bearimy](https://git.sr.ht/~pepe/bearimy) and [Marble](https://git.sr.ht/~pepe/marble)
- [jff](https://git.sr.ht/~pepe/jff.git)
- [janet-filesystem](https://github.com/jeannekamikaze/janet-filesystem)
- [remarkable](https://github.com/pyrmont/remarkable)
- [janet-uri](https://github.com/andrewchambers/janet-uri)
