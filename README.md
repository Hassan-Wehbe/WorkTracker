# WorkTracker — portable Salesforce package

Omni-Channel Case agent monitoring app with configurable actionable / non-actionable Case statuses.

## What is included

- WorkTracker Lightning app + LWC grid (15-day metrics)
- Columns:
  - Cases Accepted
  - Cases Rejected
  - Kept Actionable
  - Parallel Work
  - **Long-Running Kept Actionable** (still in kept-actionable status, typically New; >1 hour)
  - **Long-Running Returning** (previously left a non-actionable status; >1 hour)
- Omni Case channel, queue-based routing, presence statuses (capacity = 1)
- `WorkTracker_AgentWork__c` history object (seedable AgentWork-style records)
- Custom Metadata Type **WorkTracker Case Status** for actionable vs non-actionable mapping
- Returning detection via Case History and/or `Is_Returning__c` on work history
- Sample Case status **Open Awaiting Sales** (non-actionable) — change via CMDT in any org
- Apex seeder + tests + permission set

## Configure statuses (any org)

Setup → Custom Metadata Types → **WorkTracker Case Status**:

| Field | Meaning |
|---|---|
| Case Status | Exact `Case.Status` API value |
| Is Actionable | `true` = actionable, `false` = non-actionable |
| Counts As Kept Actionable | Counts toward Kept Actionable / Long-Running Kept Actionable (usually `New`) |

Add a row for every Case status you care about. No Apex changes required.

Also map non-actionable statuses as **COMPLETED** on the Case Service Channel (Omni status-based capacity) in Setup if you add new ones beyond the sample package mapping.

## Deploy (source format)

Unzip, then from the `WorkTracker` folder:

```bash
sf org login web -a TargetOrg
sf project deploy start -d . -o TargetOrg --test-level RunLocalTests
sf org assign permset -n WorkTracker_Access -o TargetOrg
```

### Post-deploy org setup

1. Assign **WorkTracker Access** permission set to agents/supervisors.
2. Enable **Service Cloud User** on agent users.
3. Add agents to **Case Work Queue** and assign **Case Agent Presence**.
4. Optional: enable Case Status field history tracking for automatic returning detection from Case History.
5. Optional demo data (runs as current user):

```apex
WorkTrackerDataSeeder.seed();
// or
WorkTrackerDataSeeder.seedForUsername('agent@example.com');
```

6. Open the **WorkTracker** app from the App Launcher.

## Notes

- Standard `AgentWork` accept/decline timestamps cannot be backdated via Apex; monitoring history uses `WorkTracker_AgentWork__c`.
- Queue and presence configs ship **without** hardcoded users so the package is org-portable.
- `CaseStatus` StandardValueSet includes sample statuses (`New`, `Working`, `Escalated`, `Open Awaiting Sales`, `Closed`). Review before deploying into production orgs with custom Case statuses.
