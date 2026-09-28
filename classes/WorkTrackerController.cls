public with sharing class WorkTrackerController {
    public static final Integer LOOKBACK_DAYS = 15;
    public static final Integer LONG_RUNNING_MINUTES = 60;

    public class AgentOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
    }

    public class DailyMetricRow {
        @AuraEnabled
        public String activityDate;
        @AuraEnabled
        public Integer acceptedCount;
        @AuraEnabled
        public Integer rejectedCount;
        @AuraEnabled
        public Integer keptActionableCount;
        @AuraEnabled
        public Integer parallelWorkCount;
        @AuraEnabled
        public Integer longRunningKeptActionableCount;
        @AuraEnabled
        public Integer longRunningReturningCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<AgentOption> getAgentOptions() {
        List<AgentOption> options = new List<AgentOption>();

        for (User agentUser : [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true AND UserPermissionsSupportUser = true
            WITH SECURITY_ENFORCED
            ORDER BY Name
            LIMIT 200
        ]) {
            AgentOption option = new AgentOption();
            option.id = agentUser.Id;
            option.name = agentUser.Name;
            options.add(option);
        }

        if (options.isEmpty()) {
            User currentUser = [
                SELECT Id, Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            AgentOption option = new AgentOption();
            option.id = currentUser.Id;
            option.name = currentUser.Name;
            options.add(option);
        }

        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<DailyMetricRow> getDailyMetrics(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('Select an agent to view WorkTracker metrics.');
        }

        Date startDate = Date.today().addDays(-(LOOKBACK_DAYS - 1));
        DateTime startDateTime = DateTime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));

        List<WorkTracker_AgentWork__c> acceptedWork = [
            SELECT Id, Case__c, Accept_DateTime__c, Close_DateTime__c, Parallel_Group__c, Is_Long_Running__c, Is_Returning__c
            FROM WorkTracker_AgentWork__c
            WHERE OwnerId = :userId
                AND Accept_DateTime__c >= :startDateTime
                AND Work_Status__c IN ('Accepted', 'Closed')
            WITH SECURITY_ENFORCED
        ];

        List<WorkTracker_AgentWork__c> declinedWork = [
            SELECT Id, Case__c, Decline_DateTime__c
            FROM WorkTracker_AgentWork__c
            WHERE OwnerId = :userId
                AND Decline_DateTime__c >= :startDateTime
                AND Work_Status__c = 'Declined'
            WITH SECURITY_ENFORCED
        ];

        Set<Id> acceptedCaseIds = new Set<Id>();
        for (WorkTracker_AgentWork__c work : acceptedWork) {
            if (work.Case__c != null) {
                acceptedCaseIds.add(work.Case__c);
            }
        }

        Map<Id, Case> casesById = new Map<Id, Case>();
        if (!acceptedCaseIds.isEmpty()) {
            casesById = new Map<Id, Case>([
                SELECT Id, Status
                FROM Case
                WHERE Id IN :acceptedCaseIds
                WITH SECURITY_ENFORCED
            ]);
        }

        Set<Id> returningCaseIds = WorkTrackerStatusConfig.getReturningCaseIds(acceptedCaseIds);

        return buildDailyMetrics(
            startDate,
            acceptedWork,
            declinedWork,
            casesById,
            returningCaseIds
        );
    }

    @TestVisible
    private static List<DailyMetricRow> buildDailyMetrics(
        Date startDate,
        List<WorkTracker_AgentWork__c> acceptedWork,
        List<WorkTracker_AgentWork__c> declinedWork,
        Map<Id, Case> casesById,
        Set<Id> returningCaseIds
    ) {
        Map<Date, DailyMetricRow> rowsByDate = buildEmptyRows(startDate);
        Map<Date, Set<String>> parallelGroupsByDate = new Map<Date, Set<String>>();
        Set<Id> safeReturningIds = returningCaseIds == null ? new Set<Id>() : returningCaseIds;

        for (WorkTracker_AgentWork__c work : acceptedWork) {
            if (work.Accept_DateTime__c == null) {
                continue;
            }

            Date acceptDay = work.Accept_DateTime__c.date();
            if (!rowsByDate.containsKey(acceptDay)) {
                continue;
            }

            DailyMetricRow row = rowsByDate.get(acceptDay);
            row.acceptedCount++;

            Case caseRecord = casesById.get(work.Case__c);
            Boolean isReturning =
                work.Is_Returning__c == true ||
                (work.Case__c != null && safeReturningIds.contains(work.Case__c));
            Boolean isKeptActionable =
                caseRecord != null && WorkTrackerStatusConfig.isKeptActionableStatus(caseRecord.Status);

            if (isKeptActionable && !isReturning) {
                row.keptActionableCount++;
            }

            Boolean longRunning =
                work.Is_Long_Running__c == true || isLongRunningDuration(work, caseRecord);

            if (longRunning && caseRecord != null && !WorkTrackerStatusConfig.isNonActionableStatus(caseRecord.Status)) {
                if (isReturning) {
                    row.longRunningReturningCount++;
                } else if (isKeptActionable) {
                    row.longRunningKeptActionableCount++;
                }
            }

            if (String.isNotBlank(work.Parallel_Group__c)) {
                if (!parallelGroupsByDate.containsKey(acceptDay)) {
                    parallelGroupsByDate.put(acceptDay, new Set<String>());
                }
                parallelGroupsByDate.get(acceptDay).add(work.Parallel_Group__c);
            }
        }

        for (Date day : parallelGroupsByDate.keySet()) {
            Integer parallelMembers = 0;
            for (WorkTracker_AgentWork__c work : acceptedWork) {
                if (
                    work.Accept_DateTime__c != null &&
                    work.Accept_DateTime__c.date() == day &&
                    String.isNotBlank(work.Parallel_Group__c)
                ) {
                    parallelMembers++;
                }
            }
            rowsByDate.get(day).parallelWorkCount = parallelMembers;
        }

        for (WorkTracker_AgentWork__c work : declinedWork) {
            if (work.Decline_DateTime__c == null) {
                continue;
            }

            Date declineDay = work.Decline_DateTime__c.date();
            if (rowsByDate.containsKey(declineDay)) {
                rowsByDate.get(declineDay).rejectedCount++;
            }
        }

        List<DailyMetricRow> results = new List<DailyMetricRow>();
        for (Integer offset = 0; offset < LOOKBACK_DAYS; offset++) {
            results.add(rowsByDate.get(startDate.addDays(offset)));
        }
        return results;
    }

    @TestVisible
    private static Boolean isLongRunningDuration(
        WorkTracker_AgentWork__c work,
        Case caseRecord
    ) {
        if (work.Accept_DateTime__c == null || caseRecord == null) {
            return false;
        }

        DateTime endPoint = work.Close_DateTime__c == null ? DateTime.now() : work.Close_DateTime__c;
        Long minutesOpen = (endPoint.getTime() - work.Accept_DateTime__c.getTime()) / 60000;
        return minutesOpen >= LONG_RUNNING_MINUTES;
    }

    @TestVisible
    private static Map<Date, DailyMetricRow> buildEmptyRows(Date startDate) {
        Map<Date, DailyMetricRow> rowsByDate = new Map<Date, DailyMetricRow>();
        for (Integer offset = 0; offset < LOOKBACK_DAYS; offset++) {
            Date day = startDate.addDays(offset);
            DailyMetricRow row = new DailyMetricRow();
            row.activityDate = String.valueOf(day);
            row.acceptedCount = 0;
            row.rejectedCount = 0;
            row.keptActionableCount = 0;
            row.parallelWorkCount = 0;
            row.longRunningKeptActionableCount = 0;
            row.longRunningReturningCount = 0;
            rowsByDate.put(day, row);
        }
        return rowsByDate;
    }
}
