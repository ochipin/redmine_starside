# Redmine Starside

**English** | [日本語](README.ja.md)

**A small plugin that adds [Starlight](https://starlight.astro.build/)-style banners, step lists, tabs, and checkboxes to Redmine wikis and tickets.**

Plain Redmine wiki text gets monotonous fast — everything is the same weight, and it's hard to make a warning stand out or lay a procedure out clearly. This plugin gives you a handful of wiki macros that add good-looking callout banners, numbered step lists, and tabbed content, plus an automatic checkbox notation so you can write task lists naturally. The look is borrowed from Astro's Starlight documentation theme.

Everything is rendered locally. There is no external CDN or API call, so **it works as-is in closed environments with no internet access (on-premise / internal networks).**

## Features

**Callout banners**
Four banner styles — `tip`, `note`, `warning`, and `danger` — each with its own color and icon, for making notes and warnings stand out. The title is optional, and the body is rendered as Textile / Markdown, so emphasis, links, and lists all work inside a banner.

**Step lists**
Turn an ordinary numbered list into a clean procedure view, with circled step numbers connected by a vertical line. Handy for installation steps and operational runbooks where the order matters.

**Tabs**
Show several pieces of content as switchable tabs — for example per-OS commands or Markdown/Textile variants of the same thing. Tabs are operable by mouse and by keyboard (arrow keys, Home, End, Enter, Space), with proper ARIA roles for accessibility.

**Checkbox notation**
Write `[ ]` and `[x]` in the body and they are automatically rendered as checkbox icons (☐ / ☑). It follows the live preview as you type, and notation inside code blocks is left untouched so code examples stay intact. Textile sometimes turns `[X]` into a link; when that happens, the plugin quietly rescues it and shows a checked box instead.

## Tested environment

- Redmine 6.1 (Propshaft environment)
- Text formatting: both Markdown and Textile are supported (select under "Administration > Settings > General")
- No external dependencies; works fully offline

## Directory layout

```
redmine_starside/
├── init.rb                          # Plugin registration + ViewHook + wiki macro definitions
├── assets/
│   ├── javascripts/starside.js      # Tab interaction + checkbox rendering
│   └── stylesheets/starside.css     # Styles for banners / steps / tabs
├── LICENSE
├── README.md
└── README.ja.md
```

## Installation

### Step 1: Place the plugin

Put the `redmine_starside` directory under Redmine's `plugins/`.

```
<REDMINE_ROOT>/plugins/redmine_starside/
```

### Step 2: Restart Redmine

Restart your web server (Puma / Passenger, etc.). No migration is required.

The plugin's `init.rb` registers a ViewHook that loads `starside.css` and `starside.js` into every page's `<head>` automatically, so **there is no manual asset copy or symlink step.**

### Verify

Open a wiki or ticket edit screen and write a banner such as the one below, then preview it. If a colored callout box appears, it worked.

```
{{note(Hello)
It works.
}}
```

## Usage

### Banners

Highlighted callout boxes for notes and warnings. Pass the title as an argument and the body as the macro block content. The body is rendered as Textile / Markdown.

```
{{note(Heads up)
Write the body here. **Emphasis** and links work too.
}}
```

If you omit the title, the type name (Tip / Note / Warning / Danger) is used by default.

```
{{warning
Example with the title omitted.
}}
```

You can also pass the body as the second argument, which is handy for short one-liners.

```
{{tip(Tip, A one-line note.)}}
```

| Macro | Purpose | Color |
|-------|---------|-------|
| `tip` | Tips, hints | Purple |
| `note` | Notes, remarks | Blue |
| `warning` | Cautions | Yellow |
| `danger` | Danger, warnings | Red |

### Step lists

Write a normal numbered list in the body and it is rendered as a connected, numbered procedure.

```
{{step
# First step
# Next step
# Last step
}}
```

### Tabs

Give the tab names as comma-separated arguments, and separate the body sections with `+++`.

```
{{tabs(Tab A, Tab B, Tab C)
Content for Tab A.
+++
Content for Tab B.
+++
Content for Tab C.
}}
```

Any missing tab names are auto-filled as `Tab 1`, `Tab 2`, and so on.

### Checkbox notation

The following notation is converted into checkbox icons within wiki content, previews, and ticket comments.

| Notation | Rendered |
|----------|----------|
| `[ ]` | ☐ (unchecked) |
| `[x]` `[X]` `[*]` | ☑ (checked) |

```
[ ] A task not done yet
[x] A completed task
```

Notation inside code blocks (`<pre>` / `<code>`) is left untouched, so `[ ]` written as a code example stays as-is.

## Uninstall

1. Remove `plugins/redmine_starside/`
2. Restart Redmine

You'll be back to plain wiki rendering.

## License

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.
