# GIT OPS

## Git mirror bundle

Usage: `./git-mirror-bundle.sh --remote <URL>`

### Steps

1. Clone repository using [--mirror](https://www.git-scm.com/docs/git-clone#Documentation/git-clone.txt---mirror) 
> --mirror  
> Set up a mirror of the source repository. This implies `--bare`. Compared to `--bare`, `--mirror` not only maps local 
> branches of the source to local branches of the target, it maps all refs (including remote-tracking branches, notes 
> etc.) and sets up a refspec configuration such that all these refs are overwritten by a `git remote update` in the 
> target repository.

2. Bundle repository using [--all](https://git-scm.com/docs/git-bundle)
> If you want to match `git clone --mirror`, which would include your refs such as `refs/remotes/*`, use `--all`.

3. Upload to Google Storage (optional)

Usage: `./git-mirror-bundle.sh --remote <URL> --gstorage <PREFIX>`

## GitHub

### Sync all repos from a GitHub organization

Clones all repos into a local directory. Already-cloned repos are updated with `git fetch --all`.

Requires the [gh CLI](https://cli.github.com/) authenticated with `gh auth login`.

```sh
./github-org-sync.sh Anyline ~/Documents/github-Anyline
```

Add `--dry-run` to preview what would happen without making any changes:

```sh
./github-org-sync.sh Anyline ~/Documents/github-Anyline --dry-run
```

#### Excluding repos

Add repo names (one per line) to either of these files:

- `excluded-github-repos.txt` — committed, shared across the team
- `excluded-github-repos.local.txt` — gitignored, personal/local overrides

Lines starting with `#` are treated as comments and ignored.
