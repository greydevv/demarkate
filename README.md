# demarkate
A markup parser for blog-style documents.

### Goals
- [ ] **Promote [ADA Compliance](https://www.ada.gov/law-and-regs/design-standards/)**

Ensure the AST is flexible enough such that any downstream renderer can
maintain compliance and function properly with assistive technoloy like screen
readers.

- [ ] **Helpful errors** (TODO)

Because the parser enforces rigid rules, it should give the user helpful error
information.

- [ ] **Friendly to Vim/Emacs-like editors**

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

### Directives

Directives take the following form:
```
@identifier:attributes<content; parameters>
```

_Attributes_ are always optional and _parameters_ are enforced depending on the
type of directive.

### URLs
```
@url<text; https://www.example.com>
```

### Images

```
@img<alt-text; https://www.example.com>
@img<alt-text; /some/relative/path.jpg>
```
If the image is purely decorative, use the `decorative` attribute and omit the alt-text:
```
@img:decorative<; https://www.example.com>
                ^ don't forget the semicolon!
```

### Block Code
```
@code<
    let x = 13;
    print(x);
>
```
Specify an optional language as the first attribute:
```
@code:zig<
    const std = @import("std");
>
```
