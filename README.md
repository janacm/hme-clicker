# HideMyEmailClicker
A macOS utility to quickly access Hide My Email settings via System Settings accessibility controls.

## Build
```bash
swiftc HideMyEmailClicker.swift -o HideMyEmailClicker
```

## Usage
```bash
./HideMyEmailClicker [label text]
```

The optional `[label text]` argument is typed into the **LABEL** field of the
new address dialog. Arguments are joined with spaces, so quoting is optional:

```bash
./HideMyEmailClicker "My Newsletter Signup"
./HideMyEmailClicker My Newsletter Signup
```

If no argument is given, the LABEL field is left empty.

Note: You'll need to grant Accessibility permission when first running the app.
