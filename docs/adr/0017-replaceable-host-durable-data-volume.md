# Replaceable Host, durable data volume

Status: accepted

The Host is cattle, its data is not. The EC2 instance sets `user_data_replace_on_change = true`, so any change to the cloud-init bootstrap destroys and recreates the instance; the running box therefore always matches its declared bootstrap, and there is no drift between the two. App data survives because `/srv/data` lives on a separate EBS volume with `prevent_destroy` that detaches cleanly (`stop_instance_before_detaching`) and re-attaches to the replacement, while the root volume (OS plus `/var/lib/docker`) is a disposable throwaway. The EIP re-associates, so the public IP is stable across replacements.

The alternative was `ignore_changes` on user data: no surprise replacements in a plan, but bootstrap edits would accumulate as manual tweaks over SSM sessions, the box would drift from the declared config, and the eventual rebuild would be the risky, untested path. The trade-off accepted here is 5 to 15 minutes of downtime per bootstrap change, which ADR 0001 already tolerates for instance replacement generally. This stance is what M10's snapshot and restore strategy builds on: snapshots target only the data volume, and the restore drill is the same operation as a routine bootstrap change.

_Source: M2 design spec (2026-07-04) §2, §6, §7._
