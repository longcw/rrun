# rrun

Sync the folder you are in to a remote host, run a command there, and stream its output back. The command runs detached on the host, so a dropped connection never kills it: `rrun attach` picks the stream up again, and Ctrl-C stops the remote command and waits for it to finish.

Made for iterating on code that has to run somewhere else than your laptop, such as a voice agent that needs a fast link to its model providers.

```
$ rrun uv run python examples/voice_agents/basic_agent.py dev
[rrun] syncing /Users/me/code/agents -> root@vps:~/agents
  livekit-agents/livekit/agents/voice/agent_session.py
  1 file(s) changed
[rrun] synced (.env through env_filter)
[rrun] starting on root@vps: uv run python examples/voice_agents/basic_agent.py dev
2026-09-06 07:30:31 - INFO livekit.agents - registered worker {...}
^C[rrun] stopping agents (Ctrl-C again to kill)
2026-09-06 07:30:50 - INFO livekit.agents - shutting down worker {...}
[rrun] exited with code 130
```

## Install

rrun is one bash script. The installer copies it to `~/.local/bin/rrun` and seeds `~/.config/rrun/config`; it keeps no checkout.

```
gh api repos/longcw/rrun/contents/install.sh -H 'Accept: application/vnd.github.raw' | bash   # while the repo is private
curl -fsSL https://raw.githubusercontent.com/longcw/rrun/main/install.sh | bash               # once it is public
```

From a checkout, `./install.sh` does the same. `rrun update` re-runs the installer over the installed copy. Requirements: bash 3.2+, ssh, rsync locally; bash, rsync, `setsid` on the host (`rrun setup` installs rsync with apt, dnf, yum, apk, or pacman).

## Commands

| Command | What it does |
|---|---|
| `rrun <command...>` | sync, then run the command on the host and stream its logs |
| `rrun attach` (or `logs`) | re-attach to the running command: last 200 lines, then follow |
| `rrun stop` | send SIGINT and stream logs until the command has exited |
| `rrun kill` | send SIGKILL |
| `rrun status` | what is running for this project on the host |
| `rrun ps` | every rrun-managed run on the host |
| `rrun killall` | stop every rrun-managed run on the host (SIGINT, then SIGKILL after 30 s) |
| `rrun sync` | rsync only |
| `rrun exec <command...>` | run attached with a tty: interactive things, installers that prompt, `htop` |
| `rrun sh` | a shell in the remote project dir |
| `rrun setup` | install rsync on the host if missing, create the project dir, sync |
| `rrun init` | write a commented `.rrun.conf` template |
| `rrun -H <host> ...` | use another host for this invocation |

While streaming, the first Ctrl-C sends SIGINT to the remote process group and keeps streaming until the group is gone. A second Ctrl-C sends SIGKILL. If the ssh stream dies, rrun reconnects and resumes from the last line it printed. Starting a new run first stops the previous one for the same project.

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
```

Then `rrun -H gpu ...`, or just `rrun ...` for the default. Connections are multiplexed through `~/.rrun/cm-*`, so repeated calls cost a few milliseconds.

**`.rrun.conf`** in the project root (optional, bash syntax) pins the project:

```bash
host=vps                                      # a name from the config, or "user@host [ssh options]"
dir=~/agents                                  # default: ~/rrun/<folder name>
env="UV_PYTHON=3.13 PYTHONUNBUFFERED=1"       # exported before every remote command
env_filter() { sed 's/^LIVEKIT_URL=.*/LIVEKIT_URL=wss:\/\/prod.example/'; }   # optional
```

The project root is the nearest parent with a `.rrun.conf`, else the git top level, else the current directory. Its basename is the project `name`, which keys the run state on the host under `~/.rrun/<name>/` (`log`, `pid`, `cmd`, `exit`).

`env_filter`, if defined, receives the local `.env` on stdin and its output is written as the remote `.env`. Use it when the same checkout should point at a different backend from the host.

## What gets synced

Everything in the project root except what git ignores and `.git` itself. `.env` and `.env.local` are synced even though they are usually git-ignored. Files deleted locally are deleted on the host.

**`.rrunignore`** adjusts that, one pattern per line in rsync syntax, `!pattern` re-includes:

```
data/          # never upload
!models/       # upload even though git ignores it
```

A folder that is not a git repo is synced whole, minus `.rrunignore`.

## How it works

Each ssh call ships a small bash library with `declare -f` and runs one function with `bash -s`, so nothing is installed on the host. The command is started with `setsid` under a wrapper that traps SIGINT, records the exit code, and stays the process-group leader, so `kill -- -pgid` reaches the whole tree. The local side tails the log through ssh in a subshell that ignores SIGINT, counts the lines it has shown, and reconnects from that line if the stream breaks.
