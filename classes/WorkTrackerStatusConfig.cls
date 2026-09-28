public with sharing class WorkTrackerStatusConfig {
    @TestVisible
    private static List<WorkTracker_Case_Status__mdt> testStatusRows;

    private static List<WorkTracker_Case_Status__mdt> cachedRows;

    public static List<WorkTracker_Case_Status__mdt> getStatusRows() {
        if (testStatusRows != null) {
            return testStatusRows;
        }
        if (cachedRows == null) {
            cachedRows = [
                SELECT DeveloperName, MasterLabel, Case_Status__c, Is_Actionable__c, Counts_As_Kept_Actionable__c
                FROM WorkTracker_Case_Status__mdt
                ORDER BY MasterLabel
            ];
        }
        return cachedRows;
    }

    public static Set<String> getNonActionableStatuses() {
        Set<String> statuses = new Set<String>();
        for (WorkTracker_Case_Status__mdt row : getStatusRows()) {
            if (row.Is_Actionable__c == false && String.isNotBlank(row.Case_Status__c)) {
                statuses.add(row.Case_Status__c);
            }
        }
        if (statuses.isEmpty()) {
            statuses.add('Closed');
        }
        return statuses;
    }

    public static Set<String> getActionableStatuses() {
        Set<String> statuses = new Set<String>();
        for (WorkTracker_Case_Status__mdt row : getStatusRows()) {
            if (row.Is_Actionable__c == true && String.isNotBlank(row.Case_Status__c)) {
                statuses.add(row.Case_Status__c);
            }
        }
        return statuses;
    }

    public static Set<String> getKeptActionableStatuses() {
        Set<String> statuses = new Set<String>();
        for (WorkTracker_Case_Status__mdt row : getStatusRows()) {
            if (
                row.Counts_As_Kept_Actionable__c == true &&
                String.isNotBlank(row.Case_Status__c)
            ) {
                statuses.add(row.Case_Status__c);
            }
        }
        if (statuses.isEmpty() && getActionableStatuses().contains('New')) {
            statuses.add('New');
        }
        return statuses;
    }

    public static Boolean isNonActionableStatus(String statusValue) {
        if (String.isBlank(statusValue)) {
            return false;
        }
        return getNonActionableStatuses().contains(statusValue);
    }

    public static Boolean isKeptActionableStatus(String statusValue) {
        if (String.isBlank(statusValue)) {
            return false;
        }
        return getKeptActionableStatuses().contains(statusValue);
    }

    public static Boolean isActionableStatus(String statusValue) {
        if (String.isBlank(statusValue)) {
            return false;
        }
        if (isNonActionableStatus(statusValue)) {
            return false;
        }
        Set<String> actionable = getActionableStatuses();
        if (actionable.isEmpty()) {
            return true;
        }
        return actionable.contains(statusValue);
    }

    public class StatusTransition {
        public Id caseId;
        public String oldStatus;
        public String newStatus;
    }

    /**
     * A Case is "returning" when Case History shows it previously moved out of a
     * configured non-actionable status (for example back to New/Working).
     */
    public static Set<Id> getReturningCaseIds(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new Set<Id>();
        }

        List<StatusTransition> transitions = new List<StatusTransition>();
        for (CaseHistory historyRow : [
            SELECT CaseId, OldValue, NewValue
            FROM CaseHistory
            WHERE CaseId IN :caseIds AND Field = 'Status'
        ]) {
            StatusTransition transition = new StatusTransition();
            transition.caseId = historyRow.CaseId;
            transition.oldStatus = historyRow.OldValue == null ? null : String.valueOf(historyRow.OldValue);
            transition.newStatus = historyRow.NewValue == null ? null : String.valueOf(historyRow.NewValue);
            transitions.add(transition);
        }

        return collectReturningCaseIds(transitions, getNonActionableStatuses());
    }

    @TestVisible
    private static Set<Id> collectReturningCaseIds(
        List<StatusTransition> transitions,
        Set<String> nonActionableStatuses
    ) {
        Set<Id> returningCaseIds = new Set<Id>();
        if (transitions == null || transitions.isEmpty() || nonActionableStatuses == null) {
            return returningCaseIds;
        }

        for (StatusTransition transition : transitions) {
            if (
                transition != null &&
                transition.caseId != null &&
                String.isNotBlank(transition.oldStatus) &&
                nonActionableStatuses.contains(transition.oldStatus) &&
                isActionableStatus(transition.newStatus)
            ) {
                returningCaseIds.add(transition.caseId);
            }
        }
        return returningCaseIds;
    }

    public static String getPrimaryActionableStatus() {
        Set<String> kept = getKeptActionableStatuses();
        if (!kept.isEmpty()) {
            return new List<String>(kept)[0];
        }
        Set<String> actionable = getActionableStatuses();
        if (!actionable.isEmpty()) {
            return new List<String>(actionable)[0];
        }
        return 'New';
    }

    public static String getPrimaryNonActionableStatus() {
        for (String statusValue : getNonActionableStatuses()) {
            if (statusValue != 'Closed') {
                return statusValue;
            }
        }
        Set<String> nonActionable = getNonActionableStatuses();
        if (!nonActionable.isEmpty()) {
            return new List<String>(nonActionable)[0];
        }
        return 'Closed';
    }

    public static String getSecondaryActionableStatus() {
        String primary = getPrimaryActionableStatus();
        for (String statusValue : getActionableStatuses()) {
            if (statusValue != primary) {
                return statusValue;
            }
        }
        return primary;
    }

    @AuraEnabled(cacheable=true)
    public static StatusLegend getStatusLegend() {
        StatusLegend legend = new StatusLegend();
        legend.actionableStatuses = new List<String>(getActionableStatuses());
        legend.nonActionableStatuses = new List<String>(getNonActionableStatuses());
        legend.keptActionableStatuses = new List<String>(getKeptActionableStatuses());
        legend.actionableStatuses.sort();
        legend.nonActionableStatuses.sort();
        legend.keptActionableStatuses.sort();
        return legend;
    }

    public class StatusLegend {
        @AuraEnabled
        public List<String> actionableStatuses;
        @AuraEnabled
        public List<String> nonActionableStatuses;
        @AuraEnabled
        public List<String> keptActionableStatuses;
    }
}
