# rigid-markup

A markup parser for my blog (not yet live).

### Notes
This project is meant to solve a few recurring problems I encounter when writing markup:
- unreadable/uneditable raw markup
  - formatting rules are applied to make sure reading and editing markup is easy and consistent
- remembering all the things
  - implements directives that prioritize language, e.g. @url<text; link> and @img<alt-text; link>
- one way to do something
  - many flavors of markup allow underscores or single asterisks to delimit italic text. This parser only allows `/` for italic text.


The features of this parser adhere to the standard of "one way to do
something." In many flavors of markdown, you can use underscores or single
asterisks to delimit italic text. This parser only allows `/`. 


### Inline Modifiers

| delimiter | modification |
|:-:|-|
| `*` | **bold** |
| `/` | _italic_ |
| `_` | <u>underline</u> |
| `~` | ~~strikethrough~~ |

To display any character (except EOF) literally, use `\` (backslash).
