---
name: karchy-containers
description: Use on a karchy system when the task touches the Containers window or its launcher entry, the containers icon and panel in the bar, the `karchy containers` command (`karchy-containers`) and its JSON, or the question of which container engine (Podman or Docker) a karchy machine uses and why the window shows nothing. Also use to add or remove the Containers app (package `karchy-containers-app`, Quick install › karchy › Containers). Do not use for how karchy sets Podman up (`DOCKER_HOST`, `podman.socket`, subordinate IDs, GPU containers: use karchy-podman when that skill is present), or for virtual machines (use karchy-vms).
---

# karchy's Containers app

Containers is karchy's window for containers, images and Compose projects, with an icon in the bar while containers run. It is an app of its own (package `karchy-containers-app`, Quick install › karchy › Containers) and brings no container engine. It works with Podman or Docker, whichever the user installed. This skill comes with the app.

## Change rules

Follow the change rules in the `karchy` skill. Starting, stopping and restarting a container and `compose up` are small changes: do them, then say what changed. These count as large, so describe them and get the user's agreement first:

- Pruning: `karchy containers prune` runs `system prune --force` with no question.
- Removing containers, images or volumes the user did not ask about.
- Installing or removing an engine, or the app. Which engine to use is the user's choice.

## Find the engine first

```bash
karchy containers engines    # {"engine":"podman","also":"","cli":"docker"}
```

| Field | Meaning |
| --- | --- |
| `engine` | `podman`, `docker`, or `""` when neither is installed |
| `also` | `docker` when both are installed, else `""` |
| `cli` | the command to type for the engine in use: `docker` when that reaches it, else `podman` |

`karchy containers engine` prints only the name and fails when there is none.

| What is installed | What the app does |
| --- | --- |
| Neither | The window says no container engine is installed and opens Quick install at Podman and Docker. Every `karchy containers` command but `open`, `engine` and `engines` exits 3 with one sentence. The bar icon never shows. |
| Podman | Uses it. With karchy's Podman setup (`karchy-podman`), `docker` is Podman too (`podman-docker`), so `cli` is `docker`. Podman installed by hand has no `docker` command: `cli` is `podman`. |
| Docker | Uses it. `list`, `summary` and `images` exit 4 with one sentence when Docker does not answer: its service is not running, or the user is not in the `docker` group in this session yet (Quick install adds the group, which applies at the next sign-in). The window shows that sentence. |
| Both | Uses Podman, because it runs as the user with no service to start and no group to join. The window and the panel say that Docker is installed too. Docker's containers are not listed; use `docker ps` for them. To make the app show Docker's, the user removes Podman. |

Both engines are in Quick install › System: **Podman** is karchy's setup (`karchy quick-install install podman`: rootless, with the `docker` command and Compose), **Docker** is Docker itself (`karchy quick-install install docker`). The two can't be installed together, because `podman-docker` conflicts with `docker`; Quick install refuses the second and names the first.

After a switch from karchy's Podman setup to Docker, the running session keeps Podman's `DOCKER_HOST` until the next sign-in. A `docker` command in an open terminal then fails with "Cannot connect to the Docker daemon at unix:///run/user/…/podman/podman.sock". `karchy containers` ignores that leftover; for a terminal, `unset DOCKER_HOST` or sign out and in again.

## Add or remove the app

```bash
pacman -Q karchy-containers-app          # is it installed?
karchy quick-install install containers  # adds the app only, with sudo
karchy quick-install remove containers   # removes the app only
```

Removing the app leaves the engine, its containers, images and volumes alone. It takes the launcher entry and this skill. The bar icon and `karchy containers` are part of karchy and stay.

## The karchy containers command

`karchy containers` (the same program as `karchy-containers`) is what the panel and window call. It answers in one JSON shape for Podman and for Docker. Its header in `/usr/share/karchy/bin/karchy-containers` documents the shapes.

```bash
karchy containers list              # every container and Compose project, as JSON
karchy containers summary           # running containers only
karchy containers images
karchy containers logs <container> [lines]
karchy containers start|stop|restart|remove <container>
karchy containers compose up|down|restart <project>
karchy containers forget <project>
karchy containers open [container]  # the Containers window
```

- For ordinary work use the engine's own command (`cli` above) directly. Use `karchy containers` to read state as JSON or to act on a Compose project by name from any folder.
- Compose projects are found from the labels Compose puts on containers. Their folder and files are remembered in `~/.local/state/karchy/containers/projects.json`, so `compose up <project>` works after `down`. `forget` drops a project from that file and does nothing to containers.
- `compose up` fails with "compose file … is gone" when the remembered file no longer exists. Start the project from its folder instead.
- A failed action also sends a desktop notification with the last lines of the error.
- `follow` and `open` need the desktop session. `watch` streams events and does not return.

## Panel and window

The bar shows a Containers icon with a count only while containers run. Its panel lists up to six running containers with a run switch and an "Open <port>" action. The window (`karchy containers open`, or Containers in the app launcher) has stopped containers, Compose projects, images, logs, remove and prune. Both follow container events, so no refresh is needed after a command.

If the icon does not appear after an engine was installed outside Quick install, run `karchy-shell -q karchy.containers refresh`.
