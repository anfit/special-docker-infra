# special-docker-infra

Terraform that provisions the AWS side of [special-docker](../special-docker): the DynamoDB table, the log group, and an EC2 docker host with a least-privilege role. It deliberately does **not** decide:

* **where releases come from** beyond the default of a public GHCR image (`image_repository` + `registry_auth`; see [`docs/REGISTRY_OPTIONS.md`](docs/REGISTRY_OPTIONS.md) for the free, no-private-server options and a release-strategy menu), or
* **anything specific to your AWS ecosystem** (account, profile, tags, state backend). Those live in git-ignored files you create from `templates/`.

> **Status:** `terraform init`, `validate` and `fmt` pass (Terraform 1.16.5, AWS provider 5.x), and the first-boot script renders and passes `bash -n` for all three `registry_auth` modes. It has **not** been planned or applied against a real AWS account. (`special-docker/deploy/aws/special-stack.yaml` is an equivalent, CloudFormation-based path that stays as a single-file alternative.)

## What it creates

| Module | Resources |
|---|---|
| `modules/data` | DynamoDB table (on-demand, PITR, TTL on `ttl`, deletion protection, GSIs `gsi1`/`gsi2`), CloudWatch log group |
| `modules/host` | optional dedicated VPC + public subnet, security group (80/443 only), IAM role + profile (table, SSM prefix, log group, SSM core; ECR read only when `registry_auth = "ecr"`), EC2 (AL2023, IMDSv2, encrypted gp3), Elastic IP, first-boot script installing Docker, Compose and the `special-deploy` command |

No SSH, no access keys, no secrets in Terraform state: the application key and any registry token are SSM `SecureString` parameters that you create by hand.

## Not committed (use the templates)

| Template | Copy to | Holds |
|---|---|---|
| `templates/terraform.tfvars.example` | `terraform.tfvars` | account, region, profile, domain, image repository |
| `templates/tags.auto.tfvars.example` | `tags.auto.tfvars` | your tagging strategy (applied via provider `default_tags`) and an optional `required_tag_keys` policy check |
| `templates/backend.tf.example`, `backend.hcl.example` | `backend.tf`, `backend.hcl` | remote state (S3) |

`.gitignore` excludes all of these plus state files. Commit `.terraform.lock.hcl` once generated.

## Use

```text
cp templates/terraform.tfvars.example terraform.tfvars        # edit
cp templates/tags.auto.tfvars.example tags.auto.tfvars        # edit
terraform init
terraform plan
terraform apply
```

Then:

1. Create the DNS A record `domain_name → public_ip`.
2. Create secrets (see the special-docker AWS guide, sections 6 and 9):
   `aws ssm put-parameter --name <ssm_prefix>/app-key --type SecureString --value "$(openssl rand -base64 48)"`; for `registry_auth = "ssm"` also `<ssm_prefix>/registry-user` and `<ssm_prefix>/registry-token`.
3. Publish a release image (your choice, see the options doc), then deploy it:
   `aws ssm start-session ...` (output `connect_command`) and `sudo special-deploy <tag-or-sha256:digest>`, or run output `deploy_command` from anywhere.
4. Create the first admin and verify, as in special-docker's `docs/AWS_SETUP.md` (sections 9–10).

## Operations

| Task | How |
|---|---|
| New release | publish image, `special-deploy <tag>`; roll back by deploying the previous tag/digest |
| Pin to an immutable build | `special-deploy sha256:<digest>` |
| Rebuild the host | `terraform apply -replace='module.host.aws_instance.this'` (state is in DynamoDB; Caddy re-issues its certificate; users sign in again) |
| Second environment | new tfvars/workspace with a different `name`, `ssm_prefix`, `domain_name` |
| Restore data | see special-docker `docs/AWS_SETUP.md` ("Backups and restore"); the instance role already allows tables named `<table>*` |
| Tear down | set `table_deletion_protection = false`, apply, then `terraform destroy` (the table and its backups go with it) |

User data and the AMI are `ignore_changes` on the instance on purpose, so editing them never replaces a running host by surprise.

## Compatibility with special-docker

The host relies on three things in the image: `/opt/special-deploy/{compose.prod.yml,Caddyfile,deploy.sh}`, `deploy.sh` honouring `/opt/special/registry-login.sh` and `sha256:` digests (both present in special-docker since commit "deploy.sh accepts image digests"), and the DynamoDB schema in `src/Storage/DynamoSchema.php`. `modules/data/main.tf` repeats that schema; keep them in sync.
