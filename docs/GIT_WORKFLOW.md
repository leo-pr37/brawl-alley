# Git Workflow

This repo follows the shared GitHub project update policy.

## Default path

- Pull latest `main` before starting work.
- Use feature/fix/docs/chore branches for meaningful changes.
- Review `git status`, `git diff`, and `git diff --check` before committing.
- Run available test/lint/build checks before pushing.
- Use Conventional Commits, e.g. `fix: correct webhook retry`.
- Push the branch and open a PR for code/product/infra/security changes.
- Squash merge after CI is green.

## Direct-to-main exception

Direct commits to `main` are only for low-risk docs/notes/template updates after the diff is reviewed.

## Safety

Never commit secrets, raw `.env` files, private keys, tokens, cookies, session state, database dumps, or unencrypted backups.

Canonical policy: `/home/leo/leo-brain/docs/github-project-policy.md`
Audit command: `/home/leo/leo-brain/scripts/git-project-policy-audit.sh --fetch`
