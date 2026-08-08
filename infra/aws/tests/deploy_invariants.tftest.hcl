variables {
  alert_email = "alerts@example.invalid"
}

# M6 pipeline guard-rails (ADR 0024, F-001). Everything here is asserted at PLAN
# time, so each value is derived from vars/locals or account+region data, never
# a computed resource ARN (cf. security_invariants for why some invariants must
# instead be checked against live state). The trust policy embeds the OIDC
# provider ARN, which is known-after-apply for a fresh provider, so the sub is
# asserted through the plan-known ci_sub_pattern output rather than by decoding the
# trust document.

run "ci_role_trust_is_main_ref_only_for_one_repo" {
  command = plan

  # The hello CI role trusts exactly one repo's main ref: nothing wider, no
  # wildcard ref, no second repo. caddy has no CI role at all.
  assert {
    condition     = module.hello.ci_sub_pattern == "repo:etoews@634901/wkx-hello@1327570828:ref:refs/heads/main"
    error_message = "The hello CI role must trust exactly the wkx-hello repo's main ref by immutable id (sub repo:etoews@634901/wkx-hello@1327570828:ref:refs/heads/main): pinned owner, repo, and ids, main ref only, no wildcards."
  }

  assert {
    condition     = module.caddy.ci_role_arn == null
    error_message = "The caddy module was instantiated without a github_repo, so it must create no CI role."
  }
}

run "ci_role_grants_are_scoped_and_exclude_state" {
  command = plan

  # PutObject is confined to this service's own deploy-bucket prefix.
  assert {
    condition = anytrue([
      for s in jsondecode(module.hello.ci_role_policy).Statement :
      try(s.Sid, "") == "DeployBundlePutOwnPrefix" &&
      try(s.Action, "") == "s3:PutObject" &&
      try(endswith(s.Resource, "/deploy/hello/*"), false)
    ])
    error_message = "The CI role's s3:PutObject must be scoped to deploy/<service>/* on the deploy bucket."
  }

  # ECR push is confined to this service's own repository.
  assert {
    condition = anytrue([
      for s in jsondecode(module.hello.ci_role_policy).Statement :
      try(s.Sid, "") == "EcrPushPullThisRepo" &&
      try(endswith(s.Resource, ":repository/wkx/hello"), false)
    ])
    error_message = "ECR push must be scoped to the project's own wkx/<service> repository."
  }

  # F-001: no statement grants anything on the Terraform state bucket. State
  # carries the DNS-01 token, so a state-reading CI role would be zone control.
  assert {
    condition     = !strcontains(module.hello.ci_role_policy, "tfstate")
    error_message = "The CI role must never reference the Terraform state bucket in any statement."
  }
}

run "lifecycle_and_deploy_bucket_hardening" {
  command = plan

  # The single expiry rule: all images older than 30 days.
  assert {
    condition = anytrue([
      for r in jsondecode(module.hello.lifecycle_policy).rules :
      r.selection.tagStatus == "any" &&
      r.selection.countUnit == "days" &&
      r.selection.countNumber == 30
    ])
    error_message = "ECR lifecycle must expire all images older than 30 days."
  }

  # Plus the untagged-cleanup rule.
  assert {
    condition = anytrue([
      for r in jsondecode(module.hello.lifecycle_policy).rules :
      r.selection.tagStatus == "untagged"
    ])
    error_message = "ECR lifecycle must include an untagged-cleanup rule."
  }

  # Immutability and scan-on-push survive the migration into the module.
  assert {
    condition = alltrue([
      module.caddy.image_tag_mutability == "IMMUTABLE",
      module.hello.image_tag_mutability == "IMMUTABLE",
      module.caddy.scan_on_push,
      module.hello.scan_on_push,
    ])
    error_message = "ECR repos must stay IMMUTABLE and scan-on-push after the module migration."
  }

  # The deploy bucket keeps versioning enabled (bundle history / rollback).
  assert {
    condition     = aws_s3_bucket_versioning.deploy.versioning_configuration[0].status == "Enabled"
    error_message = "The deploy bucket must have versioning enabled."
  }
}
