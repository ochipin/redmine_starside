# Redmine Starside

**English** | [日本語](README.ja.md)

**A small plugin that adds [Starlight](https://starlight.astro.build/)-style banners, step lists, tabs, checkboxes, and tech-stack badges to Redmine wikis and tickets.**

This plugin gives you a handful of wiki macros that add good-looking callout banners, numbered step lists, tabbed content, and tech-stack badges, plus an automatic checkbox notation so you can write task lists naturally. The look is borrowed from Astro's Starlight documentation theme.

Everything except badges is rendered locally, with no external CDN or API call, so **the core features work as-is in closed environments with no internet access (on-premise / internal networks).** The badge macro uses [shields.io](https://shields.io/) by default, but can be pointed at a self-hosted shields instance for closed networks (see [Badges](#badges)).

## Features

**Callout banners**
Four banner styles — `tip`, `note`, `warning`, and `danger` — each with its own color and icon, for making notes and warnings stand out. The title is optional, and the body is rendered as Textile / Markdown, so emphasis, links, and lists all work inside a banner.

**Step lists**
Turn an ordinary numbered list into a clean procedure view, with circled step numbers connected by a vertical line. Handy for installation steps and operational runbooks where the order matters.

**Tabs**
Show several pieces of content as switchable tabs — for example per-OS commands or Markdown/Textile variants of the same thing. Tabs are operable by mouse and by keyboard (arrow keys, Home, End, Enter, Space), with proper ARIA roles for accessibility.

**Checkbox notation**
Write `[ ]` and `[x]` in the body and they are automatically rendered as checkbox icons (☐ / ☑). It follows the live preview as you type, and notation inside code blocks is left untouched so code examples stay intact. Textile sometimes turns `[X]` into a link; when that happens, the plugin quietly rescues it and shows a checked box instead.

**Tech-stack badges**
Drop a badge with `{{badge(docker)}}` and get a shields.io-style badge with the right brand color and logo. Around 90 keys are built in (operating systems, languages, databases, container/CI tooling, and more), and you can attach a version with `{{badge(redmine, 6.1+)}}`. Colors and labels can be tweaked, and new badges added, from the plugin settings screen — no code change required. Badges use shields.io by default, but can be pointed at a self-hosted shields instance for closed networks.

## Tested environment

- Redmine 6.1 (Propshaft environment)
- Text formatting: both Markdown and Textile are supported (select under "Administration > Settings > General")
- No external dependencies for the core features; works fully offline (badges optionally use shields.io — see Badges)

## Directory layout

```
redmine_starside/
├── init.rb                          # Plugin registration + ViewHook + wiki macros + badge API
├── lib/
│   ├── redmine_starside/badge.rb    # Badge logic (definitions, colors, search)
│   └── tasks/redmine_starside.rake  # Maintenance tasks (settings cleanup on uninstall)
├── app/
│   └── views/settings/_redmine_starside.html.erb  # Badge settings screen
├── config/
│   └── locales/{en,ja}.yml          # Settings screen labels
├── assets/
│   ├── javascripts/starside.js      # Tab interaction + checkbox rendering
│   └── stylesheets/starside.css     # Styles for banners / steps / tabs
├── ICONS_LICENSE.md                 # Licenses for bundled icons
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

### Badges

Display a tech-stack badge inline. The first argument is a key; an optional second argument is a version.

```
{{badge(linux)}}
{{badge(redmine)}}
{{badge(redmine, 6.1+)}}
```

A trailing `+` on the version is converted to `.*` (`6.1+` becomes `6.1.*`). Keys are case-insensitive, and several aliases are provided (`k8s` → Kubernetes, `golang` → Go, and so on).

Around 90 keys are built in, covering operating systems and distributions, languages, databases, container / CI / IaC tooling, secrets and observability tools, Google Workspace, and a few generic icons (`settings`, `maintenance`, `bug`, `network`). The full, current list of keys — along with their colors and a live preview — is shown on the settings screen.

**Customizing**
Open **Administration > Plugins > Redmine Starside > Settings** to:

- change the color of any built-in badge,
- add your own badges (including tools not covered by the defaults),
- set the badge image host ("Badge base URL").

Only your changes are stored, so plugin updates that improve the default colors still reach any badge you haven't customized.

**Closed networks**
By default, badges use `https://img.shields.io` on the internet. In a closed environment, self-host [shields](https://github.com/badges/shields) and enter your own instance's URL in the "Badge base URL" field on the settings screen. No traffic to shields.io will occur after that.

> Unlike the other macros, `badge` produces an `<img>` pointing at a badge image host. "Badge base URL" accepts an absolute URL (`https://shields.example.com`) or, behind a reverse proxy, a root-relative path (`/shields`) that resolves against the same origin as the page.

## Uninstall

1. (Optional) Remove the plugin's stored settings:
   ```
   bundle exec rake redmine_starside:uninstall_settings RAILS_ENV=production
   ```
   This is only needed if you used the badge settings screen. Leaving the row in place is harmless.
2. Remove `plugins/redmine_starside/`
3. Restart Redmine

You'll be back to plain wiki rendering.

## License

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.

Bundled icons (used by the generic badges) are from Google's Material Symbols, licensed under the Apache License 2.0. See [ICONS_LICENSE.md](ICONS_LICENSE.md).
