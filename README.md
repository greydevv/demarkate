# rigid-md

A rigid, opinionated markdown parser. Not CommonMark-compliant.

## Block Elements

### Line Breaks

Any number of line breaks can appear. Whitespace is not truncated, and the parser will not strip any line breaks from the document.

### Headings

Supports six sizes of headings. Specifying more than 6 levels will generate a parser error.

Example:
```text
### a level 3 heading
```

### Code

Use three backticks at the start of a line to delineate block-level code.

The closing set of backticks must also start on a line break, or it is an error.

````text
An example function:
```zig
pub fn foo() u32 {
    return 13;
}
```
````

## Inline Elements

For any inline element, its closing delimiter must appear before a line break. Otherwise, it is considered an unterminated element and results in a parse error.

### Code

Use a single backtick to delineate inline code
```text
To define a variable use `var x = 10;`.
```

### Italics

Use underscores to delineate italic text.
```text
I am _italic_.
```

### Bold

Use asterisks to delineate bold text.
```text
I am *bold*.
```

### Strikethrough
```text
I am ~finishsed~.
```
