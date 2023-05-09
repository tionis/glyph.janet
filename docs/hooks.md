# Glyph hooks
Glyph allow you to use two kinds of hooks:
- core hooks
- module hooks
Module hooks (aka collection hooks) are defined in a collections .main.info.json file and allow a collection to register a subcommand to execute either before (pre-sync) of after (post-sync) sync. They also gain access to some metadata via their execution environment. More docs to follow here.
Core hooks modify central aspects of glyph functionality and live directly in the glyph archive itself. Currently only the setup hook is supported, which is executed when glyph is first initialized
