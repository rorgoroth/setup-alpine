# GitHub Action: Setup Alpine Linux

A [GitHub Action](https://github.com/features/actions) to easily set up and use a [chroot](https://en.wikipedia.org/wiki/Chroot)-based [Alpine Linux](https://alpinelinux.org/) **edge** environment (x86_64) in your workflows. Think of a chroot as a very simple container.

> [!NOTE]
> This is a trimmed-down fork of [jirutka/setup-alpine](https://github.com/jirutka/setup-alpine). It supports only Alpine `edge` on x86_64 Linux runners.

```yaml
runs-on: ubuntu-latest
steps:
  - uses: rorgoroth/setup-alpine@v2.0.0

  - run: cat /etc/alpine-release
    shell: alpine.sh {0}
```

_See [more examples](#usage-examples)…_


## Highlights

- **Easy to use and flexible**
  - Add one step `uses: rorgoroth/setup-alpine@v2.0.0` to set up the Alpine environment. For the steps that should run in it, specify `shell: alpine.sh {0}`. See [Usage examples](#usage-examples).
  - You can switch between one or more Alpine environments and the host system (Ubuntu) within a single job (each step can run in a different environment).

- **No hassle with Docker images**
  - You don't have to write any Dockerfiles or build and maintain custom Docker images.
  - Just install what you need (gcc, nodejs, python, …) with [apk](https://www.mankier.com/8/apk) from the [Alpine packages](https://pkgs.alpinelinux.org/packages).

- **Always up to date environment**
  - All packages are installed directly from the Alpine Linux repositories (by default from `dl-cdn.alpinelinux.org`) using [apk-tools](https://gitlab.alpinelinux.org/alpine/apk-tools/), Alpine's package manager. There's no intermediate layer, such as a Docker image, that can lag behind with security fixes.
  - Alpine `edge` is a rolling release, so two runs on different days may get different package versions.

- **Simple and lightweight**
  - A small Node.js wrapper and about 300 lines of Bash that use only basic Unix tools (chroot, mount, curl, …) and apk-tools.


## Requirements

- A Linux **x86_64** runner. On any other platform or architecture the action fails early with an error. It's tested on GitHub-hosted `ubuntu-latest` and `ubuntu-22.04`.
- Passwordless `sudo` for the runner user (as on GitHub-hosted runners), plus `curl`, `lsof` and `getent` on the host.
- For self-hosted runners: Actions Runner v2.327.1 or newer, which is the minimum for actions that run on `node24`.


## Parameters

### Inputs

#### `apk-tools-url`

URL of the apk-tools static binary to use, or `auto` to select the pinned x86_64 build (apk-tools 3.0.8).
Custom URLs must start with `https://` or `http://` and end with `#!sha256!` followed by the SHA-256 hash of the file.
This should normally be left at the default value.

Default: `auto`

#### `extra-keys`

A list of paths of additional trusted keys (for installing packages from the `extra-repositories`) to copy into _/etc/apk/keys/_.
The paths should be relative to the workspace directory (the default location of your repository when using the checkout action).
Separate multiple paths with whitespace or newlines.

Example: `.keys/pkgs@example.org-56d0d9fd.rsa.pub`

#### `extra-repositories`

A list of additional Alpine repositories to add into _/etc/apk/repositories_. The official `edge` _main_ and _community_ repositories are always added.

Example: `https://dl-cdn.alpinelinux.org/alpine/edge/testing`

#### `mirror-url`

URL of an Alpine Linux mirror to fetch packages from. The action appends `/edge/main` and `/edge/community`.

Default: `https://dl-cdn.alpinelinux.org/alpine`

#### `packages`

A list of Alpine packages to install.

Example: `build-base openssh-client`
Default: _no extra packages_

#### `shell-name`

Name of the script that runs `sh` in the Alpine chroot. It is added to `GITHUB_PATH`.
Use this name in `jobs.<job_id>.steps[*].shell` (e.g. `shell: alpine.sh {0}`) to run the step's script in the chroot.
The name must start with a letter and may contain only letters, digits and `_ . ~ + @ % -`.

Default: `alpine.sh`

#### `volumes`

A list of directories on the host system to mount bind into the chroot.
You can specify the source and destination path: `<src-dir>:<dest-dir>`.
The `<src-dir>` is an absolute path of an existing directory on the host system, `<dest-dir>` is an absolute path in the chroot (it will be created if it doesn't exist).
You can omit the latter if they're the same.

Please note that the runner's work directory (e.g. _/home/runner/work_, where your workspace is located) is always mounted, don't specify it here.

Example: `${{ steps.alpine-one.outputs.root-path }}:/mnt/alpine-one`

### Outputs

#### `root-path`

Path to the created Alpine root directory.


## How it works

- The root filesystem is created in _rootfs/alpine-edge_ in the runner user's home directory (typically _/home/runner/rootfs/alpine-edge_). If that directory already exists (e.g. when the action is used twice in a job), a unique `alpine-edge-XXXXXX` directory is used instead.
- _/proc_, _/dev_, _/sys_, the runner's work directory and any `volumes` are mounted into the chroot.
- A user with the same name and UID as the runner user is created. If _/etc/sudoers.d_ exists in the chroot (e.g. after installing `sudo` through `packages`), the user gets a passwordless sudo rule; likewise for _/etc/doas.d_ and `doas`.
- The `shell-name` script is placed in the chroot's _abin_ directory, which is added to `PATH`.
  - `alpine.sh {0}` runs the step as the unprivileged user, `alpine.sh --root {0}` as root.
  - The step runs in a login shell, so `~/.profile` is sourced. The job's environment variables and the working directory are carried into the chroot.
- When the job ends, a post step terminates processes still running in the chroot, unmounts everything and removes the directory.


## Usage examples

### Basic usage

```yaml
runs-on: ubuntu-latest
steps:
  - uses: actions/checkout@v6

  - name: Setup Alpine Linux
    uses: rorgoroth/setup-alpine@v2.0.0

  - name: Run script inside Alpine chroot as root
    run: |
      cat /etc/alpine-release
      apk add nodejs npm
    shell: alpine.sh --root {0}

  - name: Run script inside Alpine chroot as the default user (unprivileged)
    run: |
      ls -la  # as you would expect, you're in your workspace directory
      npm run build
    shell: alpine.sh {0}

  - name: Run script on the host system (Ubuntu)
    run: |
      cat /etc/os-release
    shell: bash
```

### Set up Alpine with specified packages

```yaml
- uses: rorgoroth/setup-alpine@v2.0.0
  with:
    packages: >
      build-base
      libgit2-dev
      meson
```

### Set up Alpine with packages from the testing repository

```yaml
- uses: rorgoroth/setup-alpine@v2.0.0
  with:
    extra-repositories: |
      https://dl-cdn.alpinelinux.org/alpine/edge/testing
    packages: some-pkg-from-testing
```

### Set up Alpine with a third-party repository

```yaml
- uses: rorgoroth/setup-alpine@v2.0.0
  with:
    extra-keys: .keys/pkgs@example.org-56d0d9fd.rsa.pub
    extra-repositories: https://pkgs.example.org/alpine/edge/main
    packages: some-pkg-from-example-org
```

### Set up and use multiple Alpine environments in a single job

```yaml
runs-on: ubuntu-latest
steps:
  - name: Setup the first Alpine Linux environment
    id: alpine-one
    uses: rorgoroth/setup-alpine@v2.0.0
    with:
      shell-name: alpine-one.sh

  - name: Setup the second Alpine Linux environment (with the first one mounted into it)
    uses: rorgoroth/setup-alpine@v2.0.0
    with:
      shell-name: alpine-two.sh
      volumes: ${{ steps.alpine-one.outputs.root-path }}:/mnt/alpine-one

  - name: Run script inside the first chroot
    run: cat /etc/alpine-release
    shell: alpine-one.sh {0}

  - name: Run script inside the second chroot
    run: ls /mnt/alpine-one
    shell: alpine-two.sh {0}

  - name: Run script on the host system (Ubuntu)
    run: cat /etc/os-release
    shell: bash
```


## History

This action is a fork of [jirutka/setup-alpine](https://github.com/jirutka/setup-alpine) by Jakub Jirutka, which is itself an evolution of his [alpine-chroot-install](https://github.com/alpinelinux/alpine-chroot-install) script, originally written for Travis CI in 2016.
The implementation is principally the same, but tailored to GitHub Actions.


## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
For the full text of the license, see the [LICENSE](LICENSE) file.
