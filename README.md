# special-docker-infra

Terraform that provisions the AWS side of [special-docker](https://github.com/anfit/special-docker): the DynamoDB table, the log group, and an EC2 docker host with a least-privilege role. It deliberately does **not** provide or decide:

* **the load balancer, certificate, DNS name or WAF.** TLS is the corporate edge team's responsibility; this repo provides *tie-ins* (a closed-by-default host, outputs to hand over, optional ingress from their security group, optional registration in their target group). See [special-docker `docs/EDGE_INTEGRATION.md`](https://github.com/anfit/special-docker/blob/main/docs/EDGE_INTEGRATION.md) for the contract and a request template.
* **where releases come from** beyond the default of a public GHCR image (`image_repository` + `registry_auth`; see [`docs/REGISTRY_OPTIONS.md`](docs/REGISTRY_OPTIONS.md) for the free, no-private-server options and a release-strategy menu), or
* **anything specific to your AWS ecosystem** (account, profile, tags, state backend). Those live in git-ignored files you create from `templates/`.

> **Status:** `terraform init`, `validate` and `fmt` pass (Terraform 1.16.5, AWS provider 5.x), and the first-boot script renders and passes `bash -n` for all three `registry_auth` modes. It has **not** been planned or applied against a real AWS account. (`special-docker/deploy/aws/special-stack.yaml` is an equivalent, CloudFormation-based path that stays as a single-file alternative.)

## What it creates

| Module | Resources |
|---|---|
| `modules/data` | DynamoDB table (on-demand, PITR, TTL on `ttl`, deletion protection, GSIs `gsi1`/`gsi2`), CloudWatch log group |
| `modules/host` | optional dedicated VPC + public subnet (outbound access only), security group (**no inbound rule** unless you give a source), IAM role + profile (table, SSM prefix, log group, SSM core; ECR read only when `registry_auth = "ecr"`), EC2 (AL2023, IMDSv2, encrypted gp3), first-boot script installing Docker, Compose and the `special-deploy` command; optional registration in the edge team's target groups |

No SSH, no access keys, no certificates, no secrets in Terraform state: the application key and any registry token are SSM `SecureString` parameters that you create by hand.

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

1. Create the application secret (see the special-docker AWS guide, section 5):
   `aws ssm put-parameter --name <ssm_prefix>/app-key --type SecureString --value "$(openssl rand -base64 48)"`; for `registry_auth = "ssm"` also `<ssm_prefix>/registry-user` and `<ssm_prefix>/registry-token`.
2. Publish a release image (default: the GHCR workflow in special-docker) and deploy it: run output `connect_command`, then `sudo special-deploy <version-or-sha256:digest>`, or use output `deploy_command` from anywhere.
3. Look at it and create the first administrator through the tunnel (output `port_forward_command`, then <http://localhost:8080>): the first visit goes to `/setup`; the one-time setup token is in the CloudWatch log (`app` stream).
4. **Hand over to the edge team.** `terraform output edge_integration` prints the instance, private IP, VPC, security group, port and health check to put in their request (template in special-docker `docs/EDGE_INTEGRATION.md`). Either add their load balancer's security group to `ingress_security_group_ids` (or a CIDR to `ingress_cidrs`), or, if they give you a target group, set `target_group_arns` so the instance registers itself; then `terraform apply`.
5. When their HTTPS listener is live: set `insecure_http = false` and `public_base_url` to the final URL in tfvars, apply (changes reach the host's `instance.env` only at first boot, so also edit `/opt/special/instance.env` on the host as in the AWS guide section 7, and `sudo special-deploy`). Verify `https://<name>/health` has no `warnings`.

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

The host relies on three things in the image: `/opt/special-deploy/{compose.prod.yml,Caddyfile,deploy.sh}`, `deploy.sh` honouring `/opt/special/registry-login.sh`, `sha256:` digests, and `SPECIAL_PUBLIC_BASE_URL` / `SPECIAL_INSECURE_HTTP` / `SPECIAL_TRUSTED_PROXY_HOPS` from `instance.env` (special-docker 1.1.0 and later; 1.0.0 still expects `SPECIAL_DOMAIN` and bundles Caddy, so deploy 1.1.0+ with this repo), and the DynamoDB schema in `src/Storage/DynamoSchema.php`. `modules/data/main.tf` repeats that schema; keep them in sync.
