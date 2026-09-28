@IsTest
private class WorkTrackerStatusConfigTest {
    @IsTest
    static void statusHelpersUseConfiguredMetadata() {
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

        Case probeCase = new Case(Subject = 'Return Probe', Status = 'New', Origin = 'Phone');
        insert probeCase;

        WorkTrackerStatusConfig.StatusTransition transition = new WorkTrackerStatusConfig.StatusTransition();
        transition.caseId = probeCase.Id;
        transition.oldStatus = 'Open Awaiting Sales';
        transition.newStatus = 'Working';

        Test.startTest();
        System.assertEquals(true, WorkTrackerStatusConfig.isKeptActionableStatus('New'));
        System.assertEquals(true, WorkTrackerStatusConfig.isNonActionableStatus('Open Awaiting Sales'));
        System.assertEquals(false, WorkTrackerStatusConfig.isNonActionableStatus('New'));
        System.assertEquals(true, WorkTrackerStatusConfig.isActionableStatus('Working'));
        System.assertEquals(false, WorkTrackerStatusConfig.isActionableStatus('Closed'));
        System.assertEquals('New', WorkTrackerStatusConfig.getPrimaryActionableStatus());
        System.assertEquals('Working', WorkTrackerStatusConfig.getSecondaryActionableStatus());
        System.assertEquals('Open Awaiting Sales', WorkTrackerStatusConfig.getPrimaryNonActionableStatus());

        WorkTrackerStatusConfig.StatusLegend legend = WorkTrackerStatusConfig.getStatusLegend();
        Set<Id> emptyReturning = WorkTrackerStatusConfig.getReturningCaseIds(new Set<Id>());
        Set<Id> returningIds = WorkTrackerStatusConfig.collectReturningCaseIds(
            new List<WorkTrackerStatusConfig.StatusTransition>{ transition },
            WorkTrackerStatusConfig.getNonActionableStatuses()
        );
        Set<Id> queriedReturning = WorkTrackerStatusConfig.getReturningCaseIds(
            new Set<Id>{ probeCase.Id }
        );
        Test.stopTest();

        System.assert(legend.nonActionableStatuses.contains('Open Awaiting Sales'));
        System.assert(legend.actionableStatuses.contains('Working'));
        System.assert(legend.keptActionableStatuses.contains('New'));
        System.assertEquals(0, emptyReturning.size());
        System.assert(returningIds.contains(probeCase.Id));
        System.assertNotEquals(null, queriedReturning);
    }
}
