# rrun

Sync the folder you are in to a remote host, run a command there, and stream its output back. The command runs detached on the host, so a dropped connection never kills it: `rrun attach` picks the stream up again, and Ctrl-C stops the remote command and waits for it to finish.

Made for iterating on code that has to run somewhere else than your laptop, such as a voice agent that needs a fast link to its model providers.

```
$ rrun uv run python examples/voice_agents/basic_agent.py dev
[rrun] syncing /Users/me/code/agents -> root@vps:~/agents
  livekit-agents/livekit/agents/voice/agent_session.py
  1 file(s) changed
[rrun]   .env (filtered)
[rrun] synced
[rrun] starting agents on root@vps: uv run python examples/voice_agents/basic_agent.py dev
2026-09-06 07:30:31 - INFO livekit.agents - registered worker {...}
^C[rrun] stopping agents (Ctrl-C again to kill)
2026-09-06 07:30:50 - INFO livekit.agents - shutting down worker {...}
[rrun] agents exited with code 130
```

## Install

rrun is one bash script. The installer copies it to `~/.local/bin/rrun` and seeds `~/.config/rrun/config`; it keeps no checkout.

```
curl -fsSL https://raw.githubusercontent.com/longcw/rrun/main/install.sh | bash
```

or `git clone https://github.com/longcw/rrun && rrun/install.sh`. `rrun update` re-runs the installer over the installed copy. Requirements: bash 3.2+, ssh, rsync locally; bash, rsync, and util-linux `setsid` on the host (`rrun setup` installs rsync with apt, dnf, yum, apk, or pacman). Without `setsid --fork`, Ctrl-C can only stop programs that install their own SIGINT handler.

## Commands

| Command | What it does |
|---|---|
| `rrun <command...>` | sync, then run the command on the host as the project's default run and stream its logs |
| `rrun -n <run> <command...>` | same, in a named slot shown as `<project>:<run>`, alongside the default run |
| `rrun -N <command...>` | same, in a fresh slot with a generated name |
| `rrun attach [run]` (or `logs`) | re-attach to a run: last 200 lines, then follow |
| `rrun stop [run]` | send SIGINT and stream logs until the run has exited |
| `rrun kill [run]` | send SIGKILL |
| `rrun status [run]` | is the run alive, its processes or exit code |
| `rrun ps [-a]` | this project's runs on the host; `-a` for every project |
| `rrun clean [run]` | remove the project's run state on the host, stopping anything still running; or one run |
| `rrun killall` | stop every rrun-managed run on the host (SIGINT, then SIGKILL after 30 s) |
| `rrun sync` | rsync only |
| `rrun exec <command...>` | run attached with a tty: interactive things, installers that prompt, `htop` |
| `rrun sh` | a shell in the remote project dir |
| `rrun setup` | install rsync on the host if missing, create the project dir, sync |
| `rrun init` | write a commented `.rrun.conf` template |
| `rrun -y ...` | skip the first-sync confirmation |
| `rrun -H <host> ...` | use another host for this invocation |
| `rrun -d <dir> ...` | use this remote folder for the project and remember it in `.rrun.conf` |

A project has a default run, shown by its bare project name, and starting it replaces the previous one, so a forgotten worker never lingers. `-n load` uses a second slot, shown as `agents:load`, that runs at the same time; `attach load`, `stop load`, `status load` address it. Every subcommand acts on the default run when no name is given. `-N` never replaces anything.

While streaming, the first Ctrl-C sends SIGINT to the remote process group and keeps streaming until the group is gone. A second Ctrl-C sends SIGKILL. If the ssh stream dies, rrun reconnects and resumes from the last line it printed.

Commands are joined and run through `bash -lc` in the remote project dir, so pipes and redirects work when quoted:

```
rrun 'curl -LsSf https://astral.sh/uv/install.sh | sh'
rrun exec uv sync --all-extras --dev
```

## Config

No config is needed: give `-H` an ssh target and any ssh options, and the command after them.

```
rrun -H root@vps.example.com -p 2222 -i ~/.ssh/id_ed25519 uv run python agent.py dev
```

**`~/.config/rrun/config`** gives hosts a name, one `name = target [ssh options]` per line, plus which one is the default:

```
vps = root@vps.example.com -p 22 -i ~/.ssh/id_ed25519
gpu = me@gpu-box
default = vps
root = ~/rrun
log_max = 50M
```

Then `rrun -H gpu ...`, or just `rrun ...` for the default. `root` is the parent folder for every project on the host: a project syncs to `<root>/<folder name>` unless `.rrun.conf` or `-d` says otherwise (default `~/rrun`). Connections are multiplexed through `~/.rrun/cm-*`, so repeated calls cost a few milliseconds.

**`.rrun.conf`** in the project root (optional, bash syntax) pins the project:

```bash
host=vps                                      # a name from the config, or "user@host [ssh options]"
dir=~/agents                                  # default: <root>/<folder name>; `rrun -d ~/agents ...` writes this line
env="UV_PYTHON=3.13 PYTHONUNBUFFERED=1"       # exported before every remote command
log_max=200M                                  # overrides the config's log_max for this project
filter .env "sed 's/^API_URL=.*/API_URL=https:\/\/prod.example/'"
filter config.yaml to_prod                     # any command, or a function defined in this file
to_prod() { sed 's/localhost/0.0.0.0/'; }
```

The project root is the nearest parent with a `.rrun.conf`, else the git top level, else the current directory. Its basename is the project `name`; each run keeps its state on the host under `~/.rrun/<name>/<run>/` (`log`, `pid`, `cmd`, `exit`; the default run is `default`), which stays after the run ends until that slot is started again or `rrun clean` removes it.

Logs rotate: when a run's log passes `log_max` (default 50M, settable in the config or per project, `0` disables), it is copied to `log.1` and truncated in place, so at most two files of that size exist per run. The process keeps writing to the same open file. A follower that reconnects after a rotation says so and continues from the current file.

A `filter <file> <command>` line takes that file out of rsync; instead the local file is piped through the command and the output is written to the same path on the host. Use it when the same checkout should point at a different backend from the host, for example to activate a different block of `.env`. Repeat the line for more files.

## What gets synced

The first time you run rrun in a folder that has no `.rrun.conf`, it shows the folder, the file count, and the destination, and asks before uploading anything, so a stray `rrun` in your home directory does not mirror it to the host. Confirming writes a `.rrun.conf`, which marks the folder as a project; later runs sync without asking. `-y` answers yes, and a non-interactive run without `-y` refuses instead of prompting. `rrun exec` never syncs, so it needs no project at all.

Everything in the project root except what git ignores and `.git` itself. `.env` and `.env.local` are synced even though they are usually git-ignored. Files deleted locally are deleted on the host.

**`.rrunignore`** adjusts that, one pattern per line in rsync syntax, `!pattern` re-includes:

```
data/          # never upload
!models/       # upload even though git ignores it
```

A folder that is not a git repo is synced whole, minus `.rrunignore`.

Symlinks that point inside the project stay symlinks on the host. A symlink that points outside, such as an `.env` linked from a shared location, is copied as a regular file with the target's content. A dangling link is skipped with a warning.

## How it works

Each ssh call ships a small bash library with `declare -f` and runs one function with `bash -s`, so nothing is installed on the host. The command is started with `setsid --fork` under a wrapper that traps SIGINT, records the exit code, and stays the process-group leader, so `kill -- -pgid` reaches the whole tree. `--fork` matters: a shell background job would inherit SIGINT as ignored and pass that down to the command. The local side tails the log through ssh in a subshell that ignores SIGINT, counts the lines it has shown, and reconnects from that line if the stream breaks.
