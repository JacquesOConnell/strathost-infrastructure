# 2. Straightforward service modules

**Date:** 25 November 2026. **Status:** Selected implementation style.

## Purpose

I need to understand, explain and maintain this Terraform myself. I kept service folders as small modules and made the resource definitions direct and explicit. Each resource should be understandable from its arguments and a short planning note.

## Changes

| Area | Selected approach |
|---|---|
| Security groups | Named resources such as `aws_security_group.docker_hosts`, with direct source/destination references |
| Service traffic | Explicit rules for the three proxy paths, agent flows and private service access |
| Repeated client ranges | Simple `for_each` over approved CIDRs |
| Networking inputs | AZ names in a `map(string)` and a `single_nat_gateway` boolean |
| AZ verification | Check selected names are available; output physical name-to-ID mapping for review in the approved account |
| KMS | Eight named keys and aliases; pass each reviewed policy directly to its key |
| S3 | Named buckets, encryption configurations and lifecycle rules; shared privacy/ownership/versioning controls remain a small loop |
| EFS inputs | Separate key ARN strings and a simple site-to-POSIX-ID map |
| Outputs | Return identifiers; service setup order is explicit in the composition root |

The root configuration must finish networking, security rules and storage setup before configuring EC2 services. ALB setup must wait for its logging bucket policy and encryption. Express these phase dependencies at the consuming module call rather than hiding large readiness lists inside outputs. The implemented root now expresses these dependencies directly at the consuming module calls.

## Planning relationship

The service folders from decision 1 remain selected. The diagram's topology, private data access, selected encryption, production guards and retention settings are preserved. Physical AZ IDs are now review outputs rather than duplicate inputs; the account-specific mapping must still be confirmed before deployment. This updates the proposed input contracts in plan sections 6.1 and 23, not the three-AZ requirement.

The source has not been deployed. Resource addresses were renamed during development; no AWS state migration was performed. Both the source and tests were updated, and schema validation plus all 18 mocked test runs pass. Subsequent work added IAM policy composition and the root; live authorization and service acceptance remain pending. Decision 3 supersedes the earlier mandatory NAT/origin-trust proposals.
