---
name: work-toolkit
description: The user's work shell toolkit (okcli for Okta AWS profiles and repo pins, kx for Kubernetes contexts, ctx, twin, ws, tk, hat). Use before running any aws, kubectl, helm, terraform or eks command, when a repo has an .envrc pin, when asked which AWS account/cluster/access level applies, when asked which GitHub account or Claude profile a folder uses, or when the user mentions okcli, kx, ctx, twin, ws, tk or hat.
---

# Work toolkit

A set of shell commands (`tk status` shows the toolkit's folder; `tk ls` lists every command,
including the ones its layers add: `tk layer ls`).
They decide which AWS account and role, and which Kubernetes cluster, a command runs against.
Different repos need different access levels, so get this right before touching AWS or Kubernetes.

## First: where am I pointing?

```bash
ctx plain        # AWS profile (+ PROD flag, session time left), repo pin, kube context, Twingate, GitHub
```

A session-start hook already put this in your context once. Run it again after you `cd` to
another repo, and whenever you're unsure. `PROD` means the account or cluster is production.

## The direnv catch (important)

Repo pins are an `.envrc` (`export AWS_PROFILE=...`) loaded by direnv from the shell prompt.
Your Bash tool doesn't run that prompt hook, so `AWS_PROFILE` in your environment can be stale:
it's whatever the terminal had when Claude started. `ctx plain` says
`Repo pin: X (does NOT match ...)` when that happened.

So don't trust the inherited environment. Name the profile or context on each command:

| Do this | Instead of |
|---|---|
| `okcli exec <profile> -- aws s3 ls` | `aws s3 ls` |
| `hat exec -- aws s3 ls` (uses the folder's pin) | `aws ...` after a `cd` |
| `kx exec <context> -- kubectl get pods -n <ns>` | `kubectl get pods` |
| `kubectl --context <context> -n <ns> ...` | relying on the current context |

The pin, when there is one, is the profile the user meant for that repo. Use it.
To look around, pick the account's read-only profile (`*-ro`, `*-read`); an admin or team
role only when the job needs it.

A guard hook runs before your Bash commands: it has the user approve a command that changes
something on PROD, or a bare `aws`/`kubectl` while the inherited profile or context is PROD.
When it asks, that's expected: say what the command will do and on which account. Its notes
(`work-toolkit guard: ...`) also warn when a session is about to run out.

## Which GitHub account and Claude profile (hat)

`hat show` (in a folder) says which Claude profile, GitHub account and AWS profile it uses and
where from; `hat ls` lists every folder that has one. `ctx plain` has a GitHub line: the
folder's account, whether git's email matches it, and whether `gh` is signed in as it.
`gh` itself ignores the folder and uses its own active account, so run it as
`hat exec -- gh pr create ...`: that gives `gh` the folder's account (and the folder's AWS
pin). If `ctx plain` says `gh has NO sign-in` for the account, ask the user to run
`! hat github login <account>` (browser) instead of using `gh` as the wrong account. Changing a folder's hat
(`hat set`, `hat off`) or adding/removing accounts edits ~/.gitconfig and .envrc files: only
when the user asks.

## Commands you can run freely (read-only)

| Command | Tells you |
|---|---|
| `ctx plain` | everything above, in one go |
| `okcli current` / `okcli status` / `okcli ls` | profile in use; all profiles with account, role, session |
| `okcli whoami [profile]` | asks AWS who you are (account + role ARN) |
| `kx current` / `kx status` / `kx ls` | context in use; all contexts, namespaces, which profile they sign in with |
| `kx exec <ctx> -- kx pods -n <ns>` (also `why <pod>`, `deploys`, `get <kind>`, `events`, `top`) | pods, why one is unhealthy, deployments, anything else; plain tables when there's no terminal. For logs use `kubectl logs --tail=200` (`kx logs` follows and never ends) |
| `twin current` / `twin status` | Twingate exit node (machine-wide) |
| `tk doctor` | every setup check |

## Ask the user first

- **Anything that changes or deletes on a PROD profile or context.** Read-only on prod is fine.
- `okcli pin` / `okcli unpin`: writes the repo's `.envrc`.
- `okcli default`, `kx default`: changes what *all* new terminals start on. Never do this on your own.
- `twin <code>` / `twin off`: moves the whole machine's network.
- `kx restart`, `kx shell`, `kx forward` (changes, or opens a session), and `kx secrets` (shows secret values).
- `okcli refresh` and `okcli sync` open a browser for Okta sign-in. You can't complete that.
  When a session says `expired`, ask the user to run `! okcli refresh <profile>`.
  `okcli exec`, `kx exec` and `hat exec` stop at once on an expired session and say so.

## Don't use (they're interactive pickers or per-terminal switches)

`okcli` / `kx` / `twin` / `ws` / `tk` with no arguments open an fzf picker; you have no TTY.
`okcli <profile>` and `kx <context>` switch the user's terminal through a shell function and
don't carry over to your Bash calls. Use `okcli exec` / `kx exec` instead.

## Other tools, for reference

- `ws <name>`: opens a workspace in the user's IDE. `ws ls` lists them.
- `tk install` / `tk uninstall` / `tk update`: manage the toolkit itself; interactive, user runs them.
- Profiles count as prod unless the name or account contains dev / test / stg / qa / poc.
