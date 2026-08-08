variable "service" {
  description = "Service name. The repository is named wkx/<service> and the deploy-bucket prefix is deploy/<service>/. No env dimension: one repository per service holds every env's images and the <sha> tag decides which env deploys (design spec §6)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name under etoews/ (for example \"wkx-hello\"). When set, the module creates a CI role whose OIDC trust is restricted to that one repo's main ref. Leave null for platform-owned images (for example caddy) that carry no per-app CI push role."
  type        = string
  default     = null
}

variable "oidc_provider_arn" {
  description = "ARN of the account's GitHub Actions OIDC provider. Required when github_repo is set (it is the Federated principal of the CI role's trust); ignored otherwise."
  type        = string
  default     = null
}

variable "deploy_bucket_name" {
  description = "Name of the shared deploy bucket. Required when github_repo is set: the CI role may PutObject only under deploy/<service>/. Ignored otherwise. The state bucket is deliberately never referenced (F-001, ADR 0024)."
  type        = string
  default     = null
}

variable "expire_after_days" {
  description = "Expire images older than this many days. Default 30 (ROADMAP M6). The finer per-env split for pr-* preview tags is deferred to M11 with the feature that produces those tags."
  type        = number
  default     = 30
}
