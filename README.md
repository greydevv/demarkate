# THIS REPO HAS MOVED TO [CODEBERG](https://codeberg.org/moriazoso/demarkate)

# demarkate
A markup parser for blog-style documents.

### Goals
- **Promote [ADA Compliance](https://www.ada.gov/law-and-regs/design-standards/)**

Ensure the AST is flexible enough such that any downstream renderer can
maintain compliance and function properly with assistive technoloy like screen
readers.

- **Helpful errors** (TODO)

Because the parser enforces rigid rules, it should give the user helpful error
information.

- **Friendly to Vim/Emacs-like editors**

When wrapping content, use single characters to support "surround" commands/actions.

### Drawbacks
Documents accepted by this parser are probably not optimal for large-scale
storage, mainly because of the formatting rules it enforces. For instance,
block code must be indented which incurs wasteful bytes. Thankfully, that is
not the goal of this project.

### Inline Modifiers

| delimiter | modification |
|:-:|-|
| `*` | **bold** |
| `/` | _italic_ |
| `_` | <u>underline</u> |
| `~` | ~~strikethrough~~ |
| `` ` ``| `code` |

To escape any character (except EOF), use `\`.

### WIP

Hoping to get some examples up here soon.
