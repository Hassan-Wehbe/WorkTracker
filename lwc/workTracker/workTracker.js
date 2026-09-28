import { LightningElement, wire, track } from 'lwc';
import getAgentOptions from '@salesforce/apex/WorkTrackerController.getAgentOptions';
import getDailyMetrics from '@salesforce/apex/WorkTrackerController.getDailyMetrics';
import getStatusLegend from '@salesforce/apex/WorkTrackerStatusConfig.getStatusLegend';

export default class WorkTracker extends LightningElement {
    selectedUserId;
    @track agentOptions = [];
    @track rows = [];
    agentsError;
    metricsError;
    isLoadingMetrics = false;
    actionableStatusesLabel = '';
    nonActionableStatusesLabel = '';
    keptActionableStatusesLabel = '';

    @wire(getStatusLegend)
    wiredLegend({ data, error }) {
        if (data) {
            this.actionableStatusesLabel = (data.actionableStatuses || []).join(', ');
            this.nonActionableStatusesLabel = (data.nonActionableStatuses || []).join(', ');
            this.keptActionableStatusesLabel = (data.keptActionableStatuses || []).join(', ');
        } else if (error) {
            this.actionableStatusesLabel = '';
            this.nonActionableStatusesLabel = '';
            this.keptActionableStatusesLabel = '';
        }
    }

    @wire(getAgentOptions)
    wiredAgents({ data, error }) {
        if (data) {
            this.agentOptions = data.map((agent) => ({
                label: agent.name,
                value: agent.id
            }));
            this.agentsError = undefined;

            if (!this.selectedUserId && this.agentOptions.length > 0) {
                this.selectedUserId = this.agentOptions[0].value;
            }
        } else if (error) {
            this.agentsError = error?.body?.message ?? 'Unable to load agents.';
            this.agentOptions = [];
        }
    }

    @wire(getDailyMetrics, { userId: '$selectedUserId' })
    wiredMetrics({ data, error }) {
        this.isLoadingMetrics = data === undefined && !error && Boolean(this.selectedUserId);

        if (data) {
            this.rows = data;
            this.metricsError = undefined;
            this.isLoadingMetrics = false;
        } else if (error) {
            this.rows = [];
            this.metricsError = error?.body?.message ?? 'Unable to load AgentWork metrics.';
            this.isLoadingMetrics = false;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmptyAgents() {
        return !this.agentsError && this.agentOptions.length === 0;
    }

    handleAgentChange(event) {
        this.selectedUserId = event.detail.value;
    }
}
