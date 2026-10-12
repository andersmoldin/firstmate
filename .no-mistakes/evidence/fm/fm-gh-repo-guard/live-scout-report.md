# GH_REPO pin live check

Ran the specified command once from the firstmate home, without `--repo`. Nothing was written to GitHub.

```
pwd=/private/tmp/fmlab.UJaxPs/home
GH_REPO=octocat/Hello-World
origin=https://github.com/kunchenguid/firstmate.git
gh-issue-1=https://github.com/octocat/Hello-World/pull/1
```

Finding: `gh` addressed `octocat/Hello-World` (the project repo pinned by `GH_REPO`), not the `origin` of the firstmate home (`kunchenguid/firstmate`). The pin overrides the cwd's git remote.

Recommendation: none. The pin works as intended.
