# Production Incident Response Procedure

Owner: Site Reliability Engineering. Last reviewed: 2026-08-15.

## Severity levels
- SEV1: full outage or data loss affecting customers. Page the incident commander immediately.
- SEV2: major feature degraded for many customers. Page the on-call engineer.
- SEV3: minor degradation with a workaround. Handle during business hours.

## Response steps
1. The on-call engineer acknowledges the alert within 5 minutes for SEV1 and 15 minutes for SEV2.
2. Assess customer impact using the service dashboards and logs, and declare a severity.
3. Open an incident channel named inc-YYYYMMDD-short-name and assign an incident commander.
4. Post a status update to customers and stakeholders every 30 minutes for SEV1 and every hour for SEV2 until resolved.
5. Mitigate first: roll back, fail over or disable the feature flag before searching for the root cause.

## After the incident
A blameless postmortem is required for every SEV1 and SEV2 incident. The postmortem document must be published within 5 business days and include a timeline, the root cause, customer impact, and action items with owners and due dates.
