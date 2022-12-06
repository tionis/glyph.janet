# Glyph
> NOTICE: This tool is in a very early alpha state and is still being designed.  

Glyph is a command line tool that manage your personal files for you using "collections" that implement their own managment commands. A few examples for such collection scripts can be found in the examples directory.  
The integrated wiki module helps you in managing a markdown-based personal knowledge base and is designed to be used with a commandline editor like vim (the author uses neovim in combination with vimwiki).  
 The central glyph repository manages these collections and offers some functionality that the collections management scripts can hook into.  
Most importantly glyph exposes following functionality:
- A distributed key-value store
- A key-value cache
- Node management (not implemented yet)
- Encryption key management

## Collections
Collections are simple scripts implemented in a git repository. To keep the setup simple and avoid a hard requirement on glyph, they are implemented as a simple script called `.main` that is executed from the root of the collection repository. These scripts implement all the functionality to interact with the collection and thus can be used independently from glyph.

## Documentation
Large parts of glyph are self documenting via the cli and --help flags, following things should be noted:  
- Glyph discoveres the git repo it should work on first by looking up the `GLYPH_DIR` environment variable and defaults to `$HOME/.glyph`

## Contact Me
If anyone relies on this tool, please inform me over [any communication channel](https://tionis.dev) (including GitHub issues) so that I don't push a change that crashes your workflow.
