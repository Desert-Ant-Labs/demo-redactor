# Redactor

Redact personal data in what you copy on your Mac, before it reaches a chat,
AI, or email app. Redactor runs [Redact](https://desertant.com/models/redact/)
on your Mac, so nothing you copy leaves it.

![The Redactor pill after a copy: Redacted 1 name, 1 email, and 1 phone number](docs/screenshots/pill-redacted.png)

## Install

```bash
brew tap desert-ant-labs/tap
brew install --cask redactor
```

Homebrew 6 asks you to approve a tap it has not seen before. Answering that
prompt covers Redactor, and `brew trust desert-ant-labs/tap` covers anything
Desert Ant publishes later.

Or download the [disk image](https://github.com/Desert-Ant-Labs/demo-redactor/releases/latest)
and drag Redactor to Applications. Redactor works on macOS 26 or later on Apple
Silicon. Redact (12MB) downloads on first launch.

## How it works

- **Copy** text with names, emails, phone numbers, addresses, or card and bank
  numbers, and Redactor turns them into placeholders like `[EMAIL_1]`. Click
  Unredact, or copy the same text again within 5s, to get the original back.
- **Paste** unredacted personal data into a chat, AI, or email app, and
  Redactor stops the paste until you choose Paste Redacted, Paste Anyway, or
  Cancel.
- **Copy a screenshot**, and Redactor blurs the personal data in it.
- **Copy a file** in Finder, and Redactor reads it: text, CSV, Word, PDF, and
  images. A file stays a file until you click Redact.

![The Redactor menu with the Redact, Warn, and Off switch](docs/screenshots/menu.png)

Switch between Redact, Warn, and Off in the menu. Warn tells you what it found
and leaves the copy as it is. Add your own email, phone number, and name to the
whitelist in Settings, and Redactor never flags them.

## Permissions

- **Accessibility**, to stop a paste.
- **Clipboard access**: set Redactor to always allow in System Settings >
  Privacy & Security, or macOS asks on every copy.

## Limits

- Only Command V is checked. Paste from the Edit menu, or dragging a file into
  an app, goes through.
- Terminals and code editors are not watched.
- Redact misses some names. Check anything sensitive before you share it.

## Build from source

The tasks run through [mise](https://mise.jdx.dev) (`brew install mise`).

```bash
git clone https://github.com/Desert-Ant-Labs/demo-redactor.git
cd demo-redactor
mise trust && mise install
mise run run
```

Set `REDACTOR_TEAM_ID` to your Apple developer team, or macOS asks for
Accessibility again after every build. The other tasks are `build`, `test`,
`xcode`, `package`, and `clean`.

## License

The Redactor source is MIT ([`LICENSE`](LICENSE)), and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) covers the rest. Redact is
under the [Desert Ant Labs Source-Available License](https://license.desertant.com/1.0).
