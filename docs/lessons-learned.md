# Lessons learned

Short notes on the Terraform and Azure things this lab taught me.

## Terraform

- **Replace vs update.** Some changes can be done in place; others force Terraform to destroy and recreate the resource. On a container group, the name, environment variables, and ports all force a replace. Read the plan for "forces replacement" before applying.
- **Keep data off the thing that gets replaced.** Because the world is on a file share and not in the container, replacing the container didn't lose anything.
- **References instead of hardcoding.** The share, container group, and volume all reference other resources (`azurerm_resource_group.rg.name`, `azurerm_storage_account.sa.id`, and so on). That also tells Terraform what order to create things in, so I didn't need `depends_on`.
- **Never paste keys.** The volume gets the storage key from `azurerm_storage_account.sa.primary_access_key`, so it's not in any file I commit.
- **Sensitive values still end up in state.** The storage key is in `terraform.tfstate` and in saved plan files in plain text. Marking something `sensitive` only hides it from output. That's why state, plans, and tfvars are in `.gitignore`.
- **Saved plans.** `terraform plan -out=...` then `terraform apply <file>` applies exactly what I reviewed, not a fresh plan that might differ.
- **Commit the lock file.** `.terraform.lock.hcl` records the exact provider version, so the next `init` gets the same one.
- **Dynamic blocks and `range()`.** A `dynamic "ports"` block with `for_each = range(19140, 19143)` makes one `ports` block per number. `range` doesn't include the end number, which caught me once.
- **Provider major versions change arguments.** AzureRM v4 uses `storage_account_id` on `azurerm_storage_share`. Examples online are often for older versions, so check the docs for the version you're on.
- **Quote values in string maps.** Environment variables are strings; I quote `"false"` and `"5"` even when Terraform would convert them.

## Azure

- **ACI port limits.** At most 5 ports per IP, and the same port number can't be used for both TCP and UDP.
- **ACI public IPs aren't static.** A replacement always gets a new one, and Microsoft says restart, stop/start, and platform maintenance can change it too. Anything that depends on the IP has to be updated.
- **ACI is behind NAT.** The app inside only sees a private IP, which matters for anything that tells clients what address to use.
- **Storage account names** are global, lowercase, no hyphens, and some values are case-sensitive.
- **ACI bills while running** (about $0.12/hr for 2 vCPU / 4 GB), even when nobody is using it. `az container stop` stops compute billing; storage keeps billing.
- **Logs only cover the current container.** Once it's replaced the old logs are gone unless they're sent somewhere like Log Analytics.

## General

- **Moving tags move under you.** `stable` (the image) and `LATEST` (the Bedrock version the image downloads) both changed underneath me. A Bedrock update changed the whole network protocol, which is why the guide I followed no longer worked. Pinning versions would make it reproducible.
- **Guides go out of date.** The guide was correct for RakNet. The first thing to check when something "should work" is whether the software has changed since the guide was written.
- **Compare good and bad logs.** The startup race only made sense once I put a working boot's log next to a broken one and looked for the missing line.
