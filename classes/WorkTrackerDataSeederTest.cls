@IsTest
private class WorkTrackerDataSeederTest {
    @IsTest
    static void seedCreatesCasesAndAgentWorkHistoryForCurrentUser() {
        WorkTrackerStatusConfig.testStatusRows = new List<WorkTracker_Case_Status__mdt>{
            new WorkTracker_Case_Status__mdt(
                Case_Status__c = 'New',
                Is_Actionable__c = true,
                Counts_As_Kept_Actionable__c = true
            ),
            new WorkTracker_Case_Status__mdt(
                Case_Status__c = 'Working',
                Is_Actionable__c = true,
                Counts_As_Kept_Actionable__c = false
            ),
            new WorkTracker_Case_Status__mdt(
                Case_Status__c = 'Open Awaiting Sales',
                Is_Actionable__c = false,
                Counts_As_Kept_Actionable__c = false
            ),
            new WorkTracker_Case_Status__mdt(
                Case_Status__c = 'Closed',
                Is_Actionable__c = false,
                Counts_As_Kept_Actionable__c = false
            )
        };

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Group
                WHERE Type = 'Queue' AND DeveloperName = 'Case_Work_Queue'
            ],
            'Case_Work_Queue must exist for seeder tests.'
        );

        Test.startTest();
        WorkTrackerDataSeeder.SeedResult result = WorkTrackerDataSeeder.seed();
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), result.agentId);
        System.assert(result.casesCreated > 0, 'Seeder should create cases.');
        System.assert(result.agentWorksCreated > 0, 'Seeder should create agent work rows.');
        System.assertEquals(
            result.agentWorksCreated,
            [SELECT COUNT() FROM WorkTracker_AgentWork__c WHERE OwnerId = :UserInfo.getUserId()]
        );
        System.assertEquals('New', result.keptActionableStatus);
        System.assertEquals('Open Awaiting Sales', result.nonActionableStatus);
    }
}
