# Glyph
> NOTICE: This tool is in a very early alpha state and is still being designed.  

> WARNING: This tool is currently in a rewrite of it's very central glyph module feature. More information in [issue #68](https://tasadar.net/tionis/glyph/issues/68)

Glyph is commandline tool that manages a "personal archive" for you. This personal archive is a git repository which holds your data and can also define modules that glyph loads and integrates. A few examples for such modules can be found in the examples directory.  
The integrated wiki module helps you in managing a markdown-based personal knowledge base and is designed to be used with a commandline editor like vim (the author uses neovim in combination with vimwiki).  

## Modules
Modules are simple scripts implemented in a git submodule. To keep the setup simple and avoid a hard requirement on glyph, they are implemented as a simple script called `.main` that is executed from the root of the module repository. These scripts implement all the functionality to interact with the module and thus can be used independently from git.

## Future Ideas
And these features are currently in discussion and may be implmeneted:
- embedded editor
- vim plugin

## Documentation
Large parts of glyph are self documenting via the cli and --help flags, following things should be noted:  
- Glyph discoveres the git repo it should work on first by looking up the `GLYPH_ARCH_DIR` environment variable and defaults to `$HOME/arch` if not

## Contact Me
If anyone relies on this tool, please inform me over [any communication channel](https://tionis.dev) (including GitHub issues) so that I don't push a change that crashes your workflow.
