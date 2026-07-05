# Image repos hold content-addressed <sha> tags: immutability makes a tag a
# permanent name for one image, and scan-on-push is free table stakes.
run "ecr_repos_are_immutable_and_scanned" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecr_repository.caddy.image_tag_mutability == "IMMUTABLE",
      aws_ecr_repository.hello.image_tag_mutability == "IMMUTABLE",
    ])
    error_message = "ECR tags must be immutable; tags are content-addressed shas."
  }

  assert {
    condition = alltrue([
      aws_ecr_repository.caddy.image_scanning_configuration[0].scan_on_push,
      aws_ecr_repository.hello.image_scanning_configuration[0].scan_on_push,
    ])
    error_message = "ECR repos must scan on push."
  }

  assert {
    condition = alltrue([
      aws_ecr_repository.caddy.name == "wkx/caddy",
      aws_ecr_repository.hello.name == "wkx/hello",
    ])
    error_message = "ECR repos follow the wkx/<service> naming pattern."
  }
}
