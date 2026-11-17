karchy {{VERSION}}, a {{KIND}}.

## Install

_The ISO is still being built; it appears in the assets below about 15 minutes after this page._ <!-- iso-pending -->

1. Download `karchy-{{VERSION}}-x86_64.iso` and its `.sha256` from the assets below, and check it: `sha256sum -c karchy-{{VERSION}}-x86_64.iso.sha256`.
2. Write it to a USB stick: `sudo dd if=karchy-{{VERSION}}-x86_64.iso of=/dev/sdX bs=4M oflag=sync`, with `/dev/sdX` the stick. Everything on the stick is erased.
3. Boot it in UEFI mode. The installer starts by itself. At the channel question, pick **{{CHANNEL}}**. The disk you choose is erased.

The full guide, including installing from the Arch ISO instead: [docs/installing.md](https://github.com/Nulifyer/karchy/blob/{{TAG}}/docs/installing.md).

## Update

On karchy's {{CHANNEL}} channel already: open Updates from the bar's updates indicator (or Update › Update System in the menu) and press Install, or run `karchy update`. Only karchy's changed packages download.
