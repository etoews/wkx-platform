# AWS Organizations: workload-free management account plus a platform member account

Status: accepted

The platform runs in a dedicated member account under AWS Organizations, with a fresh management account that holds no workloads (per AWS best practice). This keeps the blast radius of the management account small and isolates platform resources from the existing personal account. The trade-off is more accounts to track (the existing personal account, the new management account, and the platform member account) and two new email aliases for account roots.

_Source: design spec §8.1._
