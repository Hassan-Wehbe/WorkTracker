@IsTest
private class WorkTrackerControllerTest {
    private static void setupStatusConfig() {
        WorkTrackerStatusConfig.testStatusRows = new List<WorkTracker_Case_Status__mdt>{
            new WorkTracker_Case_Status__mdt(
                DeveloperName = 'New',
                MasterLabel = 'New',
                Case_Status__c = 'New',
                Is_Actionable__c = true,
                Counts_As_Kept_Actionable__c = true
            ),
            new WorkTracker_Case_Status__mdt(
                DeveloperName = 'Working',
                MasterLabel = 'Working',
                Case_Status__c = 'Working',
                Is_Actionable__c = true,
                Counts_As_Kept_Actionable__c = false
            ),
            new WorkTracker_Case_Status__mdt(
                DeveloperName = 'Non_Actionable',
                MasterLabel = 'Non Actionable',
                Case_Status__c = 'Open Awaiting Sales',
                Is_Actionable__c = false,
                Counts_As_Kept_Actionable__c = false
            ),
            new WorkTracker_Case_Status__mdt(
                DeveloperName = 'Closed',
                MasterLabel = 'Closed',
                Case_Status__c = 'Closed',
                Is_Actionable__c = false,
                Counts_As_Kept_Actionable__c = false
            )
        };
    }

    @IsTest
    static void getAgentOptionsReturnsUsers() {
        setupStatusConfig();
        Test.startTest();
        List<WorkTrackerController.AgentOption> options = WorkTrackerController.getAgentOptions();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'At least the running user should be returned.');
    }

    @IsTest
    static void getDailyMetricsReturnsFifteenRows() {
        setupStatusConfig();
        Test.startTest();
        List<WorkTrackerController.DailyMetricRow> rows = WorkTrackerController.getDailyMetrics(
            UserInfo.getUserId()
        );
        Test.stopTest();

        System.assertEquals(
            WorkTrackerController.LOOKBACK_DAYS,
            rows.size(),
            'WorkTracker should always return 15 daily rows.'
        );
    }

    @IsTest
    static void getDailyMetricsRequiresUserId() {
        Boolean threwException = false;

        Test.startTest();
        try {
            WorkTrackerController.getDailyMetrics(null);
        } catch (AuraHandledException expected) {
            threwException = true;
        }
        Test.stopTest();

        System.assert(threwException, 'Null user ids should raise an AuraHandledException.');
    }

    @IsTest
    static void buildDailyMetricsSplitsLongRunningKeptAndReturning() {
        setupStatusConfig();

        Case keptNewCase = new Case(Subject = 'Kept New', Status = 'New', Origin = 'Phone');
        Case awaitingSalesCase = new Case(
            Subject = 'Awaiting Sales',
            Status = 'Open Awaiting Sales',
            Origin = 'Phone'
        );
        Case returningCase = new Case(Subject = 'Returning', Status = 'Working', Origin = 'Phone');
        Case workingOnlyCase = new Case(Subject = 'Working Only', Status = 'Working', Origin = 'Phone');
        insert new List<Case>{ keptNewCase, awaitingSalesCase, returningCase, workingOnlyCase };

        Date today = Date.today();
        DateTime todayNoon = DateTime.newInstance(today, Time.newInstance(12, 0, 0, 0));

        WorkTracker_AgentWork__c keptLongRunning = new WorkTracker_AgentWork__c(
            OwnerId = UserInfo.getUserId(),
            Case__c = keptNewCase.Id,
            Work_Status__c = 'Accepted',
            Accept_DateTime__c = todayNoon.addHours(-2),
            Is_Long_Running__c = true,
            Parallel_Group__c = 'P1'
        );
        WorkTracker_AgentWork__c acceptedAwaiting = new WorkTracker_AgentWork__c(
            OwnerId = UserInfo.getUserId(),
            Case__c = awaitingSalesCase.Id,
            Work_Status__c = 'Closed',
            Accept_DateTime__c = todayNoon,
            Close_DateTime__c = todayNoon.addMinutes(20),
            Parallel_Group__c = 'P1'
        );
        WorkTracker_AgentWork__c returningLongRunning = new WorkTracker_AgentWork__c(
            OwnerId = UserInfo.getUserId(),
            Case__c = returningCase.Id,
            Work_Status__c = 'Accepted',
            Accept_DateTime__c = todayNoon.addHours(-3),
            Is_Long_Running__c = true,
            Is_Returning__c = true
        );
        WorkTracker_AgentWork__c workingLongRunning = new WorkTracker_AgentWork__c(
            OwnerId = UserInfo.getUserId(),
            Case__c = workingOnlyCase.Id,
            Work_Status__c = 'Accepted',
            Accept_DateTime__c = todayNoon.addHours(-2),
            Is_Long_Running__c = true
        );
        WorkTracker_AgentWork__c declinedCase = new WorkTracker_AgentWork__c(
            OwnerId = UserInfo.getUserId(),
            Case__c = keptNewCase.Id,
            Work_Status__c = 'Declined',
            Decline_DateTime__c = todayNoon
        );

        Map<Id, Case> casesById = new Map<Id, Case>{
            keptNewCase.Id => keptNewCase,
            awaitingSalesCase.Id => awaitingSalesCase,
            returningCase.Id => returningCase,
            workingOnlyCase.Id => workingOnlyCase
        };
        Set<Id> returningCaseIds = new Set<Id>{ returningCase.Id };

        Test.startTest();
        List<WorkTrackerController.DailyMetricRow> rows = WorkTrackerController.buildDailyMetrics(
            today.addDays(-(WorkTrackerController.LOOKBACK_DAYS - 1)),
            new List<WorkTracker_AgentWork__c>{
                keptLongRunning,
                acceptedAwaiting,
                returningLongRunning,
                workingLongRunning
            },
            new List<WorkTracker_AgentWork__c>{ declinedCase },
            casesById,
            returningCaseIds
        );
        Test.stopTest();

        WorkTrackerController.DailyMetricRow todayRow = rows[rows.size() - 1];
        System.assertEquals(4, todayRow.acceptedCount, 'Accepted works should count.');
        System.assertEquals(1, todayRow.rejectedCount, 'Declined work should count.');
        System.assertEquals(1, todayRow.keptActionableCount, 'Non-returning kept actionable should count.');
        System.assertEquals(2, todayRow.parallelWorkCount, 'Parallel group members should count.');
        System.assertEquals(
            1,
            todayRow.longRunningKeptActionableCount,
            'Only kept-actionable long-running cases should count.'
        );
        System.assertEquals(
            1,
            todayRow.longRunningReturningCount,
            'Only returning long-running cases should count.'
        );
    }
}
