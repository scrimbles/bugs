# Bugs — Infecting the perfect operating system with LISP nonsense

![Bugs mascot (courtesy of pmjv)](./bugs.png)

The Bugs mascot was drawn by [pmjv](https://triapul.cz/)

Bugs is an attempt to combine the incredibly powerful programming-interface that
is the Rob Pike's Acme Editor with the power of arbitrary keybindings.

This is done via a wrapper that launches Acme, but that directs all input to Acme
through a keybinding layer written in [StreetLISP](https://git.sr.ht/~ft/sl),
which will either (a) not recognize the input as a trigger, and pass it through
unaltered, or (b) send a NUL byte to Acme to unblock I/O and perform some action
via manipulating Acme's filesystem.

# Installation

Bugs is designed to run in one of two environments:
1. [9front](http://9front.org)
2. macOS using `plan9port`

This could conceivably be expanded to allow for use in any POSIX-compatible
system with `plan9port`, but the `bugs-mount` script would need to be modified
in order to FUSE the acme filesystem via something other than macFUSE.

## Installing `plan9port` (macOS-only)

(see p9p instructions)

## Cloning the Bugs repo

Bugs is stored as a Git repository on SourceHut, and can be cloned as follows

```sh
git clone https://git.sr.ht/~scrimbles/bugs
```

## Patching Acme

Unfortunately, there is a one line modification needed in the acme source code
in order for Bugs to function. This modification allows Bugs to send a NUL
rune in order to unblock acme when it requests input
(allowing Bugs to execute actions via modifying the Acme filesystem)
without actually inserting anything into the buffer.

![acme patch](./acme-nop.patch)

The NUL rune is previously unused, and only raises a `Runeerror`.
Altering this behavior is suboptimal, but is a minimal change in order to allow
extension without needing to directly compile new keybindings into Acme

```sh
# Patch the acme source code
./patch-acme

# Recompile acme
cd "$PLAN9/src/cmd/acme" && mk install
```

## FUSE-ing the filesystem (macOS-only)

If you are using Bugs on a mocOS system with plan9port, you must run a script
to fuse the Acme filesystem on non-9front systems.

```sh
# _after_ bugs/acme is already running
./bugs-mount
```

## Adding `bugs` to your `PATH`

This can be done any way you like, but I usually do it by symlinking the `bugs`
`rc` script into a `bin` directory already existing on my `PATH`, rather than
appending the `PATH` variable itself.

Do it however you want, I'm not a cop


# Keybindings

Presently, only the following keybindings have been added to `ddproxy.sl`:
- `C-f`: Moves cursor forward one character (note this overrides the default file-completion functionality of `C-f`)
- `C-b`: Moves cursor backward one character
- `C-n`: Moves cursor down a line, attempting to preserve column
- `C-p`: Moves cursor up a line, attemption to preserve column

# Bugs (the other kind)

## Vertical movement is naïve
When moving the cursor up or down, the cursor moves to the minimum position
between the current column and the end of the target line.

However, the "current column" is lost in between movements rather than
being cached, so if you move downward through an empty line, the cursor
will remain locked to the 0th column on all subsequent lines.

This behavior also presents when moving up.

# TODO

## Quickly append to tag
A keybinding I plan to add in the future will:
1. Move the cursor to the tag of the current window
2. Insert a newline

This is meant to allow for the quick addition of commands, so as to
reduce the amount of time it tages to run a command on a given selection,
and make mouse use optional for *this specific case*, which I think
is convenient for common operations (such as `git` commands,
running formatters, etc.)

## Run current line
Designed to be used in conjunction with the previous keybinding,
a new binding should be added that:
1. Selects the current line in its entirety
2. "Middle clicks" the selection

With these two bindings together, an Acme-compatible version of
Emacs' `M-x` binding is created, wherein one can quickly invoke
any system command without interrupting flow of thought.

There may also be some binding to return to a cursor position prior
to running the tag-append keybinding, but I'm not yet 100% convinced
of its utility. A focus event may suffice.