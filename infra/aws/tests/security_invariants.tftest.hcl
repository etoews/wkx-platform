# Encodes the non-negotiable SG invariants (CLAUDE.md invariants 2 and 3) as checks.
#
# Invariant 2 (no SSH; HTTPS-only) is asserted here at PLAN time: from_port, to_port,
# and ip_protocol are configured literals, so they are known without applying. The
# origin accepts 443 only: no port 80 (Cloudflare reaches the origin over HTTPS in
# Full-strict mode; certs are DNS-01), and never port 22.
#
# Invariant 3 (Cloudflare-only sourcing) cannot be asserted at plan time: the AWS
# provider marks aws_vpc_security_group_ingress_rule.prefix_list_id as computed
# ("known after apply"), and an apply-mode test would re-create the entire root in
# ephemeral state. That invariant is verified against the real applied state by the
# AWS CLI check in the M1 plan (Task 5: describe-security-group-rules must show a
# non-null PrefixListId on every web ingress rule).
run "web_ingress_is_https_tcp_only_no_http_no_ssh" {
  command = plan

  assert {
    condition = alltrue([
      for r in [
        aws_vpc_security_group_ingress_rule.web_https_ipv4,
        aws_vpc_security_group_ingress_rule.web_https_ipv6,
      ] : r.from_port == 443 && r.to_port == 443 && r.ip_protocol == "tcp"
    ])
    error_message = "web ingress must be TCP 443 only. No HTTP (80), no SSH (22), no other ports, ever."
  }
}
