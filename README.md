# Glyph
> NOTICE: This tool is actually in the process to be reworked completly.  

Glyph is commandline tool that manages a "personal archive" for you. This personal archive is a git repository which holds your data and can also define modules that glyph loads and integrates. There are a few default modules that are always active.  
The Wiki part of this application is kind of a commandline equivalent of Obsidian or can also be seen as a wrapper for other wiki helpers like vimwiki and uses git for syncing of different machines as well as versioning of the documents.  

In the future the wiki will be one of multiple (optional) modules including:  
- config managment
- device crypto-key managment
- the wiki itself
- timers
- many more

Large parts of glyph are self documenting via the cli and --help flags, following things should be noted:  
- Glyph discoveres the git repo it should work on first by looking up the `GLYPH_ARCH_DIR` environment variable and defaults to `$HOME/arch` if not

If anyone relies on this tool, please inform me over [any communication channel](https://tionis.dev) (including github issues) so that I don't push a change to crashes your workflow.
