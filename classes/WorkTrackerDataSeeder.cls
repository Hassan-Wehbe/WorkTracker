public with sharing class WorkTrackerDataSeeder {
    public class SeedResult {
        public Integer casesCreated;
        public Integer agentWorksCreated;
        public Id agentId;
        public String actionableStatus;
        public String nonActionableStatus;
        public String keptActionableStatus;
        public String secondaryActionableStatus;
    }

    public static SeedResult seed() {
        return seed(UserInfo.getUserId(), null);
    }

    public static SeedResult seedForUsername(String agentUsername) {
        if (String.isBlank(agentUsername)) {
            throw new AuraHandledException('Agent username is required.');
        }
        User agent = [
            SELECT Id
            FROM User
            WHERE Username = :agentUsername
            LIMIT 1
        ];
        return seed(agent.Id, null);
    }

    public static SeedResult seed(Id agentId, Id queueId) {
        if (agentId == null) {
            throw new AuraHandledException('Agent Id is required.');
        }

        SeedResult result = new SeedResult();
        result.agentId = agentId;
        result.keptActionableStatus = WorkTrackerStatusConfig.getPrimaryActionableStatus();
        result.actionableStatus = result.keptActionableStatus;
        result.secondaryActionableStatus = WorkTrackerStatusConfig.getSecondaryActionableStatus();
        result.nonActionableStatus = WorkTrackerStatusConfig.getPrimaryNonActionableStatus();

        deleteExistingSeedData(agentId);

        if (queueId == null) {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue' AND DeveloperName = 'Case_Work_Queue'
                LIMIT 1
            ];
            if (queues.isEmpty()) {
                throw new AuraHandledException(
                    'Case_Work_Queue was not found. Deploy WorkTracker Omni metadata or pass a queue Id.'
                );
            }
            queueId = queues[0].Id;
        }

        List<Case> casesToInsert = new List<Case>();

        for (Integer dayOffset = 0; dayOffset < 10; dayOffset++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-DECLINE-' + dayOffset,
                    Status = result.keptActionableStatus,
                    Origin = 'Phone',
                    OwnerId = queueId
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 12; dayOffset++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-NONACT-' + dayOffset,
                    Status = result.nonActionableStatus,
                    Origin = 'Web',
                    OwnerId = agentId
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 8; dayOffset++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-NEWKEEP-' + dayOffset,
                    Status = result.keptActionableStatus,
                    Origin = 'Phone',
                    OwnerId = agentId
                )
            );
        }

        for (Integer index = 0; index < 4; index++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-LONGRUN-' + index,
                    Status = result.keptActionableStatus,
                    Origin = 'Phone',
                    OwnerId = agentId
                )
            );
        }

        for (Integer index = 0; index < 3; index++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-RETURN-' + index,
                    Status = result.keptActionableStatus,
                    Origin = 'Phone',
                    OwnerId = agentId
                )
            );
        }

        for (Integer index = 0; index < 3; index++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-PARALLEL-A-' + index,
                    Status = index == 0 ? result.keptActionableStatus : result.secondaryActionableStatus,
                    Origin = 'Phone',
                    OwnerId = agentId
                )
            );
        }

        for (Integer index = 0; index < 2; index++) {
            casesToInsert.add(
                new Case(
                    Subject = 'WT-PARALLEL-B-' + index,
                    Status = result.nonActionableStatus,
                    Origin = 'Web',
                    OwnerId = agentId
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 14; dayOffset++) {
            Boolean nonActionable = Math.mod(dayOffset, 2) == 0;
            casesToInsert.add(
                new Case(
                    Subject = 'WT-ALT-' + dayOffset,
                    Status = nonActionable ? result.nonActionableStatus : result.secondaryActionableStatus,
                    Origin = 'Phone',
                    OwnerId = agentId
                )
            );
        }

        insert casesToInsert;

        List<Case> returningCases = new List<Case>();
        for (Case caseRecord : casesToInsert) {
            if (caseRecord.Subject != null && caseRecord.Subject.startsWith('WT-RETURN-')) {
                caseRecord.Status = result.nonActionableStatus;
                returningCases.add(caseRecord);
            }
        }
        if (!returningCases.isEmpty()) {
            update returningCases;
            for (Case caseRecord : returningCases) {
                caseRecord.Status = result.secondaryActionableStatus;
            }
            update returningCases;
        }

        result.casesCreated = casesToInsert.size();

        Map<String, Case> casesBySubject = new Map<String, Case>();
        for (Case caseRecord : casesToInsert) {
            casesBySubject.put(caseRecord.Subject, caseRecord);
        }

        List<WorkTracker_AgentWork__c> works = new List<WorkTracker_AgentWork__c>();
        DateTime nowDt = DateTime.now();

        for (Integer dayOffset = 0; dayOffset < 10; dayOffset++) {
            DateTime whenDeclined = nowDt.addDays(-dayOffset).addHours(-2);
            Case declinedCase = casesBySubject.get('WT-DECLINE-' + dayOffset);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = declinedCase.Id,
                    Work_Status__c = 'Declined',
                    Request_DateTime__c = whenDeclined.addMinutes(-3),
                    Decline_DateTime__c = whenDeclined,
                    Case_Status_At_Close__c = result.keptActionableStatus
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 12; dayOffset++) {
            DateTime whenAccepted = nowDt.addDays(-dayOffset).addHours(-5);
            Case nonActCase = casesBySubject.get('WT-NONACT-' + dayOffset);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = nonActCase.Id,
                    Work_Status__c = 'Closed',
                    Request_DateTime__c = whenAccepted.addMinutes(-2),
                    Accept_DateTime__c = whenAccepted,
                    Close_DateTime__c = whenAccepted.addMinutes(25),
                    Case_Status_At_Close__c = result.nonActionableStatus
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 8; dayOffset++) {
            DateTime whenAccepted = nowDt.addDays(-dayOffset).addHours(-1);
            Case keepCase = casesBySubject.get('WT-NEWKEEP-' + dayOffset);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = keepCase.Id,
                    Work_Status__c = 'Accepted',
                    Request_DateTime__c = whenAccepted.addMinutes(-1),
                    Accept_DateTime__c = whenAccepted,
                    Case_Status_At_Close__c = result.keptActionableStatus
                )
            );
        }

        for (Integer index = 0; index < 4; index++) {
            DateTime whenAccepted = nowDt.addHours(-(3 + index)).addMinutes(-15);
            Case longRunCase = casesBySubject.get('WT-LONGRUN-' + index);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = longRunCase.Id,
                    Work_Status__c = 'Accepted',
                    Request_DateTime__c = whenAccepted.addMinutes(-4),
                    Accept_DateTime__c = whenAccepted,
                    Is_Long_Running__c = true,
                    Case_Status_At_Close__c = result.keptActionableStatus
                )
            );
        }

        for (Integer index = 0; index < 3; index++) {
            DateTime whenAccepted = nowDt.addHours(-(4 + index));
            Case returningCase = casesBySubject.get('WT-RETURN-' + index);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = returningCase.Id,
                    Work_Status__c = 'Accepted',
                    Request_DateTime__c = whenAccepted.addMinutes(-5),
                    Accept_DateTime__c = whenAccepted,
                    Is_Long_Running__c = true,
                    Is_Returning__c = true,
                    Case_Status_At_Close__c = result.secondaryActionableStatus
                )
            );
        }

        DateTime parallelStart = nowDt.addDays(-1).addHours(-4);
        for (Integer index = 0; index < 3; index++) {
            Case parallelCase = casesBySubject.get('WT-PARALLEL-A-' + index);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = parallelCase.Id,
                    Work_Status__c = 'Accepted',
                    Parallel_Group__c = 'PARALLEL-A',
                    Request_DateTime__c = parallelStart.addMinutes(-2),
                    Accept_DateTime__c = parallelStart.addMinutes(index),
                    Close_DateTime__c = index == 2 ? parallelStart.addMinutes(90) : null,
                    Is_Long_Running__c = index == 0,
                    Case_Status_At_Close__c = parallelCase.Status
                )
            );
        }

        DateTime parallelBStart = nowDt.addDays(-3).addHours(-2);
        for (Integer index = 0; index < 2; index++) {
            Case parallelCase = casesBySubject.get('WT-PARALLEL-B-' + index);
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = parallelCase.Id,
                    Work_Status__c = 'Closed',
                    Parallel_Group__c = 'PARALLEL-B',
                    Request_DateTime__c = parallelBStart.addMinutes(-1),
                    Accept_DateTime__c = parallelBStart.addMinutes(index * 2),
                    Close_DateTime__c = parallelBStart.addMinutes(40),
                    Case_Status_At_Close__c = result.nonActionableStatus
                )
            );
        }

        for (Integer dayOffset = 0; dayOffset < 14; dayOffset++) {
            DateTime whenAccepted = nowDt.addDays(-dayOffset).addHours(-6);
            Case altCase = casesBySubject.get('WT-ALT-' + dayOffset);
            Boolean nonActionable = Math.mod(dayOffset, 2) == 0;
            works.add(
                new WorkTracker_AgentWork__c(
                    OwnerId = agentId,
                    Case__c = altCase.Id,
                    Work_Status__c = nonActionable ? 'Closed' : 'Accepted',
                    Request_DateTime__c = whenAccepted.addMinutes(-2),
                    Accept_DateTime__c = whenAccepted,
                    Close_DateTime__c = nonActionable ? whenAccepted.addMinutes(18) : null,
                    Case_Status_At_Close__c = altCase.Status
                )
            );
        }

        insert works;
        result.agentWorksCreated = works.size();
        return result;
    }

    private static void deleteExistingSeedData(Id agentId) {
        delete [
            SELECT Id
            FROM WorkTracker_AgentWork__c
            WHERE OwnerId = :agentId
        ];

        delete [
            SELECT Id
            FROM Case
            WHERE Subject LIKE 'WT-%'
               OR Subject LIKE 'WorkTracker Omni Sample%'
               OR Subject = 'AgentWork Insert Probe'
        ];
    }
}
