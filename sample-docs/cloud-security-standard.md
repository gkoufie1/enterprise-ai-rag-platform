# Cloud Security Standard

Owner: Security Engineering. Last reviewed: 2026-07-30.

## Identity and access
All cloud access uses single sign-on with MFA. Long-lived access keys for IAM users are prohibited; workloads must use IAM roles. Permissions follow least privilege: policies grant only the actions and resources a workload needs, and wildcard actions on production resources require a Security Engineering exception.

## Data protection
All data must be encrypted at rest with AWS-managed or customer-managed KMS keys, and in transit with TLS 1.2 or later. S3 buckets must block public access unless Security Engineering approves a public website bucket.

## Logging and monitoring
CloudTrail must be enabled in every account and region, with logs delivered to the central logging account. Application logs are retained for at least 30 days, and audit logs for one year.

## Deployment
All infrastructure is defined as code and deployed through a CI/CD pipeline. Container images and dependencies are scanned for vulnerabilities before deployment; critical findings block the release. Manual changes in the console are only allowed during an incident and must be recorded in the incident timeline.
