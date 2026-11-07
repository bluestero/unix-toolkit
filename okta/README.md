# okcli

Name, switch and refresh your Okta AWS profiles from the terminal.
A thin layer over [okta-aws-cli](https://github.com/okta/okta-aws-cli).

```
$ okcli ls
╭─ okcli · aws profiles ──────────────────────── ● this terminal  ◆ default  1 expired → okcli refresh ─╮
│    PROFILE        ACCOUNT                  ID             ROLE             ENV    SESSION                 │
├───────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│  ● shop-dev       acme-shop-dev            111111111111   DeveloperTeam    dev    ✓ 3h41m left  ◆ default │
│    shop-dev-ro    acme-shop-dev            111111111111   ReadOnlyAccess   dev    ✓ 3h41m left            │
│    shop-ro        acme-shop                222222222222   ReadOnlyAccess   prod   ✗ expired               │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

- **Short names** for every account and role combination (`shop-dev`, not `arn:aws:iam::...`)
- **One login refreshes everything**: `okcli refresh`
- **Interactive picker**: type `okcli`, then filter, then press enter
- **A global default**: `okcli default shop-dev` is what new terminals start on; switching only changes this shell
- **Per-repo profiles**: `okcli pin shop-dev` and that repo always uses it (via direnv)
- **Safe by default**: nothing is written to `[default]`, prod accounts are flagged, expired credentials prompt a refresh

## Install

okcli is part of the work toolkit and shares its look (`lib/ui.sh`), so install it with the
toolkit, not on its own:

```bash
./install.sh            # from the toolkit folder; tick "commands"
okcli doctor
```

Requirements: `okta-aws-cli` (v2+). Recommended: `fzf` (picker), `direnv` (pins), `aws` (`whoami`).
The toolkit's shell hook loads `okta/shell/okcli.sh`, which lets `okcli` change `AWS_PROFILE` in
your current terminal and adds tab completion.

Okta settings: your company's [layer](../README.md#layers) sets these. Without one, once in
your shell rc (ask your team for the values):

```bash
export OKTA_AWSCLI_ORG_DOMAIN=<your-org>.okta.com
export OKTA_AWSCLI_OIDC_CLIENT_ID=<client id>
```

The rest have defaults in `okta/shell/okta-env.sh` (browser sign-in, 4h sessions); anything you
set yourself wins.

## Set up your profiles: `okcli sync`

```bash
okcli sync
```

Signs in to Okta once, lists **every account + role you have**, and shows a checklist (all ticked).
Enter saves the ticked ones to `~/.okta/okta.yaml`, already signed in. Run it again any time:
new roles show up as `new`, nothing is duplicated, and your default follows renames.

Names are `<account>-<role>`, from the AWS account alias and the role name:

| Account / role | Profile |
|---|---|
| acme-shop-dev / DeveloperTeam | `shop-dev-developer` |
| acme-shop-dev / ReadOnlyAccess | `shop-dev-ro` |
| acme-platform / BillingAdmin | `plat-billing-admin` |
| acme-management-account / AdministratorAccess | `mgmt-admin` |
| acme-shop / eks-shop-prod-read | `eks-shop-prod-read` (role already names its environment) |

The rules live in `~/.config/okcli/naming.conf` (written on first sync; a layer can bring its
company's version through `OKCLI_NAMING_DEFAULT`): text replacements for accounts (`acme- =`,
`platform = plat`), short forms for roles (`ReadOnlyAccess = ro`). Edit, re-run `okcli sync`.

`okcli refresh` with 3+ profiles also uses this single sign-in for all of them.

## Add a profile by hand

```bash
okcli add                                         # interactive: name, account picker, role
okcli add shop-dev-ro acme-shop-dev ReadOnlyAccess
okcli add shop-ro 222222222222 ReadOnlyAccess     # account ID works too
```

Or edit `~/.okta/okta.yaml` directly (`okcli edit`). It's the same file okta-aws-cli uses:

```yaml
awscli:
  profiles:
    shop-dev-ro:
      aws-iam-idp: "arn:aws:iam::111111111111:saml-provider/Okta-IdP"
      aws-iam-role: "arn:aws:iam::111111111111:role/ReadOnlyAccess"
  idps:   # optional: friendly account names shown in the ACCOUNT column and the add picker
    "arn:aws:iam::111111111111:saml-provider/Okta-IdP": "acme-shop-dev"
```

Then `okcli refresh`.

## Commands

Same words as every toolkit command (`okcli help` shows them all). Anything else is an error.

| Command | What it does |
|---|---|
| `okcli` | Picker (enter: switch, ctrl-r: refresh + switch, ctrl-d: make default) |
| `okcli <profile>` | Switch this terminal |
| `okcli ls` | Every profile with account, role and session |
| `okcli status` | What this terminal is using |
| `okcli current` | The active profile, name only |
| `okcli refresh [p...]` | Log in once and refresh all (or just these). `--expired`, `--current` |
| `okcli whoami [p]` | `aws sts get-caller-identity` |
| `okcli off` | No profile in this terminal |
| `okcli default [p]` / `default off` | Show / set / clear what new terminals start on |
| `okcli pin [p]` / `okcli unpin` | Pin a profile to the current folder (`.envrc` + direnv) |
| `okcli exec <p> -- cmd` | Run one command under a profile without switching |
| `okcli sync` | Discover all account+role combos, tick, save (names by convention) |
| `okcli add` / `rename` / `remove` / `edit` | Manage profiles |
| `okcli env <p>` | Print `export AWS_PROFILE=...` (for scripts) |
| `okcli doctor` | Check your setup |
| `okcli help` / `okcli help setup` | Built-in guide |

## How it works

- `okcli refresh` runs `okta-aws-cli web --profile <name> ...` for each profile. The first one
  opens the browser; the rest reuse okta-aws-cli's cached access token, so it's one login.
- Credentials go to `~/.aws/credentials` under each profile's short name, with an expiry stamp
  okcli reads for the SESSION column.
- Switching (`okcli <profile>`) exports `AWS_PROFILE` in this terminal only.
- `okcli default <p>` writes `~/.config/okcli/default`; new terminals start on it. A prod default
  needs confirmation.
- **Precedence:** a repo pin (`.envrc`) wins while you're in that repo, then whatever you switched
  to in this shell, then the default.
- For the prompt, the shell hook exports the active profile as `OKCLI_AWS`, `OKCLI_AWS_PROD` or
  `OKCLI_AWS_EXPIRED` (exactly one), so starship can color it.
- Profiles count as **prod** unless the name or account label matches
  `dev|test|sbx|sandbox|lab|stag|stg|qa|poc`. Override this with `OKCLI_NONPROD_PATTERN`.
- Prompt: starship's `aws` module shows the profile automatically. Without starship, add
  `PS1='$(_okcli_ps1)'"$PS1"` after sourcing the hook.

## Environment overrides

| Variable | Default |
|---|---|
| `OKCLI_OKTA_YAML` | `~/.okta/okta.yaml` |
| `AWS_SHARED_CREDENTIALS_FILE` | `~/.aws/credentials` |
| `OKCLI_NONPROD_PATTERN` | `dev\|test\|sbx\|sandbox\|lab\|stag\|stg\|qa\|poc` |
| `NO_COLOR` | unset (set it to disable colors) |
