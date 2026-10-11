# Getting a release onto the host without running a private Docker server

**Constraints:** free (or pennies), nothing to operate, no release strategy decided yet, and `special-docker` will live on GitHub.

The host only needs one thing from a release: *an image it can start*. Everything below is a different way to carry that image from "built" to "on the EC2 host". This repo's `image_repository` / `registry_auth` variables cover options 1–4 today; options 5–7 need a small, specific change to the host's `special-deploy` wrapper (noted per option).

## The options

| # | Option | Cost | Server to run | Auth the host needs | Immutable artifact | Works today |
|---|---|---|---|---|---|---|
| 1 | **GHCR, public package** (`ghcr.io/<owner>/special-docker`) | free | none | none | yes (digest) | yes: `registry_auth = "none"` |
| 2 | **GHCR, private package** | free within plan quota (see below) | none | read-only token in SSM | yes | yes: `registry_auth = "ssm"` |
| 3 | **Docker Hub**: one private repo is free, public is unlimited | free | none | access token in SSM (private) or none (public) | yes | yes: `ssm` / `none` |
| 4 | **GitLab container registry** (mirror the repo to GitLab.com) | free tier | none | deploy token in SSM | yes | yes: `ssm` |
| 5 | **S3 image tarball**: CI runs `docker save`, uploads to a private bucket; host does `aws s3 cp` + `docker load` | cents/month | none | **none** (instance role) | yes (S3 version + sha256) | needs wrapper change |
| 6 | **Build on the host from a git tag**: host clones the repo (read-only deploy key) and runs `docker build` | free | none | deploy key in SSM | no (rebuilt), mitigated by `composer.lock` and a pinned base image | needs wrapper change |
| 7 | **GitHub Release asset**: CI attaches the `docker save` tarball to the release; host downloads it | free (public repo) | none | none (public) / token (private) | yes | needs wrapper change |
| 8 | **ECR**: AWS-managed private registry (nothing to operate) | ~$0.10/GB-month after a small free tier (a few images ≈ pennies) | none | **none** (instance role) | yes | yes: `registry_auth = "ecr"` |

### Notes that matter

**1. GHCR public.** Simplest possible: no tokens, no expiry, anonymous pulls, unlimited. The image contains the application source and Composer dependencies and **no secrets** (configuration arrives at runtime from SSM), so the only question is whether you are comfortable with the *code* being world-readable. If special-docker's GitHub repo is going to be public anyway, this is the obvious choice.

**2. GHCR private.** Free accounts get a small quota (about 500 MB storage and 1 GB/month of data transfer outside GitHub Actions at the time of writing: check current GitHub Packages limits). One image is on the order of 200 MB, so the quota supports only a handful of deploys a month. Fine for a quiet internal tool, tight otherwise. Pull access needs a PAT (`read:packages`); fine-grained tokens expire (at most a year), so schedule a rotation reminder.

**3. Docker Hub.** The free plan includes one private repository and has anonymous pull rate limits that do not matter for one host. Needs an access token if private. Namespace is separate from GitHub, which is mildly annoying.

**4. GitLab.** Works, but means mirroring or moving CI; only attractive if you already use GitLab.

**5. S3 tarball.** The most AWS-native zero-credential option: the host already has an IAM role, so there is no token to create, leak or rotate. CI authenticates to AWS with GitHub's OIDC (no stored keys) and uploads `special-<version>.tar.zst` plus its `.sha256`. `special-deploy` verifies the checksum, runs `docker load`, then continues as today. A compressed image is ~80 MB, so a year of releases costs cents (and a lifecycle rule can expire old ones). Terraform for the bucket and the OIDC role would live in this repo. Cost: one more moving part (the bucket + OIDC trust) and a slightly slower deploy (download + load, ~30 s).

**6. Build on the host.** Nothing to publish, nothing to store: a release is a git tag and `special-deploy v1.2.0` does `git fetch`, `git checkout`, `docker build`, then the usual compose update. A t3.small builds this image in a few minutes without disturbing the running containers. The trade-off is philosophical: what runs on the host is *built there* rather than *tested elsewhere then shipped*, so builds are only as reproducible as the base image tag and the lock file. A read-only GitHub **deploy key** (SSH, per repository, no expiry) is simpler than a PAT.

**7. Release asset.** Option 5 with GitHub as the store. Free and public-friendly, but the host must download over the public internet with a token if the repo is private, and nothing stops you deleting assets by mistake.

**8. ECR.** Mentioned for completeness because it is the lowest-friction thing on AWS and there is no server to run, but it *is* a private registry you pay a few cents for. If "no private docker server" means "no infrastructure I have to maintain", ECR qualifies; if it means "no registry at all", pick 1, 5 or 6.

### Recommendation

Decide on one question: **may the application code be public?**

* **Yes** → option 1 (GHCR public). Zero credentials anywhere, nothing to maintain. Start here.
* **No, and I want no tokens at all** → option 5 (S3 tarball + OIDC). Everything authenticates with IAM.
* **No, and I want the least machinery** → option 6 (build on the host with a deploy key), accepting less artifact immutability.

Option 2/3 are fine stop-gaps for a private image if you accept managing one read-only token.

Because the host takes an `image_repository` (and optionally a registry login script) and nothing else, **switching between 1–4 later is a variable change**, not a rebuild of the stack.

## Release strategy (independent of where the image lives)

You said none is decided; these are the pieces to pick from, in increasing weight.

1. **Tags are releases.** Merge to `main` freely; cut a release by pushing a semver tag `vMAJOR.MINOR.PATCH`. CI (GitHub Actions) builds on that tag and publishes the artifact. No long-lived release branches; `main` stays releasable.
2. **Two channels from one pipeline.** `main` publishes a moving `edge` tag (and the commit sha) for a dev environment; `v*` tags publish immutable versions for prod. A second Terraform workspace/tfvars (`name = "special-dev"`) gives you the dev environment for a few dollars a month.
3. **Promote the artifact, never rebuild it.** Prod runs exactly what dev ran: deploy by digest (`special-deploy sha256:...`; supported) or by an immutable version tag. Treat `latest`/`edge` as labels, not deploy targets for prod.
4. **Deploy trigger.** Start manual: `special-deploy <tag>` over SSM Session Manager, or the `deploy_command` output (SSM send-command) from your workstation. Later, a `workflow_dispatch` GitHub Action assuming an OIDC role can run the same send-command, so "deploy" is a button with an audit trail.
5. **Rollback is redeploying the previous tag/digest.** Data is in DynamoDB and the schema is additive, so rolling the container back is safe as long as a release does not rewrite existing items (such releases should say so in their notes and ship a backfill/undo script).
6. **Release notes.** GitHub Releases generated from merged PRs/commits is enough; record anything that touches DynamoDB key formats or IAM permissions explicitly, because those need an infra apply as well as a deploy.

### Starter CI for option 1 or 2 (GHCR), for the `special-docker` repository

```yaml
# .github/workflows/release.yml  (in special-docker)
name: release
on:
  push:
    tags: ["v*"]
    branches: [main]
permissions:
  contents: read
  packages: write
jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with: { registry: ghcr.io, username: "${{ github.actor }}", password: "${{ secrets.GITHUB_TOKEN }}" }
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=raw,value=edge,enable={{is_default_branch}}
            type=sha
      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Set `image_repository = "ghcr.io/<owner>/special-docker"` (lower-case) and, for a private package, `registry_auth = "ssm"` with `<ssm_prefix>/registry-user` (your GitHub username) and `<ssm_prefix>/registry-token` (a PAT with `read:packages`).

## What I would build next, if you choose

| Choice | Work |
|---|---|
| 1 or 2 | none in this repo; add the workflow above to special-docker |
| 5 | `modules/artifacts` (bucket, lifecycle rule, GitHub OIDC provider + role), `artifact_source = "s3"` in the host wrapper (download, verify sha256, `docker load`), workflow variant that uploads |
| 6 | `artifact_source = "git"` in the host wrapper (deploy key from SSM, fetch/checkout/build), no CI needed |
