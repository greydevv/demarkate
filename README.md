# rigid-markup
A markup parser for my blog (not yet live).

### Notes
This project is meant to solve a few recurring problems I encounter when reading/writing markup:

1. **Unreadable/virtually uneditable raw markup**

This parser enforces basic formatting rules to ensure markdown is properly formatted. For example,
parsing will fail if code blocks are not indented:
```text
// error
@code:zig<
let x = 13;
>

// success
@code:zig<
    let x = 13;
>
```

2. **One way to do something**

Popular flavors of markdown allow the use of the same character for different
meanings. For example, `**this**` is bold and `*this*` is italic. Additionally,
asterisks can also be used for bulleted lists. Not only does this increase the
complexity of the parsers, but also it is a problem for vim/emacs-like editors:
actions involving surrounding characters become ambiguous and unintuitive.

### Goals
1. **Promote [ADA Compliance](https://www.ada.gov/law-and-regs/design-standards/)** (TODO)

Ensure the AST is flexible enough such that any downstream renderer can
maintain compliance and function properly with assistive technoloy like screen
readers.

2. **Friendly to Vim/Emacs-like editors**

When wrapping inline content, use single characters to support "surround" commands/actions.

3. **Helpful errors** (TODO)

Because the parser enforces rigid rules, it should give the user helpful error
information.

### Inline Modifiers

| delimiter | modification |
|:-:|-|
| `*` | **bold** |
| `/` | _italic_ |
| `_` | <u>underline</u> |
| `~` | ~~strikethrough~~ |
| `` ` ``| `code` |

To display any character (except EOF) literally, use `\` (backslash).
