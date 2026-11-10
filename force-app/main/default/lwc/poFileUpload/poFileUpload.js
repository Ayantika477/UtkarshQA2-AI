import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import createLineItemsAndStartProcessing from '@salesforce/apex/POLineItemController.createLineItemsAndStartProcessing';
import getExistingLineItems from '@salesforce/apex/POLineItemController.getExistingLineItems';
import getFileNamesForRecords from '@salesforce/apex/POLineItemController.getFileNamesForRecords';
import getLineItemStatuses from '@salesforce/apex/POLineItemController.getLineItemStatuses';

const LOADING_MESSAGES = [
    'Reading document…',
    'Locating key fields…',
    'Extracting line items…',
    'Almost done…'
];

export default class PoFileUpload extends LightningElement {
    @api recordId;

    showManualReviewModal = false;
    selectedRecordId;

    showReplacementModal = false;
    selectedReplacementRecordId;

    uploadedFiles = [];

    pollTimer;
    isPolling = false;
    pollingRecordIds = [];
    pollingFileNameMap = {};
    pollingToastShown = {};
    pollingMode = 'upload';
    batchTotal = 0;
    batchCompletedCount = 0;

    isLoading = false;
    loadingMessage = LOADING_MESSAGES[0];
    acceptedFormats = ['.pdf', '.png', '.jpg', '.jpeg'];
    loadingTimer;
    statusPollingTimer;
    processingRecordIds = [];

    existingItemsRaw = [];
    fileNameMap = {};
    isLoadingExisting = true;
    wiredExistingResult;

    @wire(getExistingLineItems, { opportunityId: '$recordId' })
    wiredItems(result) {
        this.wiredExistingResult = result;
        this.isLoadingExisting = !result.data && !result.error;
        if (result.data) {
            this.existingItemsRaw = result.data;
            this.loadFileNames(result.data);
        } else if (result.error) {
            console.error('Error loading existing PO Line Items:', result.error);
        }
    }

    loadFileNames(items) {
        const ids = items.map((i) => i.Id);
        if (ids.length === 0) {
            return;
        }
        getFileNamesForRecords({ recordIds: ids })
            .then((map) => {
                this.fileNameMap = map;
            })
            .catch((error) => {
                console.error('Error loading file names:', error);
            });
    }

    isMissing(value) {

        if (!value) {
            return true;
        }

        const val = value.trim().toLowerCase();

        return val.includes('not found')
            || val.includes('not mentioned')
            || val.includes('not available');

    }

    handleReplaceClick(event) {

        this.selectedReplacementRecordId = event.currentTarget.dataset.id;

        this.showReplacementModal = true;

    }

    handleReplacementClose() {

        this.showReplacementModal = false;

        this.selectedReplacementRecordId = null;

    }

    handleReplacementProcessSuccess() {
        this.showReplacementModal = false;
        this.selectedReplacementRecordId = null;

        refreshApex(this.wiredExistingResult)
            .catch(error => {
                console.error(error);
            });
    }

    get isProcessDisabled() {
        return this.uploadedFiles.length === 0 || this.isLoading;
    }

    get hasFiles() {
        return this.uploadedFiles.length > 0;
    }

    get fileCountLabel() {
        return `${this.uploadedFiles.length} file${this.uploadedFiles.length > 1 ? 's' : ''} ready`;
    }

    get existingItemsCount() {
        return this.existingItemsRaw.length;
    }

    get hasExistingItems() {
        return this.existingItemsRaw.length > 0;
    }

    get existingItems() {

        return this.existingItemsRaw.map(item => {

            // Show Approval Status if available, otherwise show Processing Status
            const displayStatus =
                item.Approval_Status__c &&
                    item.Approval_Status__c !== 'None'
                    ? item.Approval_Status__c
                    : item.Status__c;

            // Show Review button only until the record is submitted for approval
            const showManualReview =
                item.Status__c === 'Manual Review Required' &&
                (
                    !item.Approval_Status__c ||
                    item.Approval_Status__c === 'None'
                );

            // Replace icon should be shown only for successfully completed PO
            const replacementCount = item.PO_revision_Number__c ? Number(item.PO_revision_Number__c) : 1;
            const isReplaceableStatus = item.Status__c === 'Completed' || item.Status__c === 'Failed';
            const canReplace = isReplaceableStatus && replacementCount < 5;
            const replaceButtonLabel = item.Status__c === 'Failed' ? 'Reupload File' : 'Replace PO File';
            const showVersionTag = replacementCount > 1;
            const versionLabel = 'v' + replacementCount;
            const versionTagTitle = replacementCount >= 5
                ? 'Maximum replacements reached'
                : (5 - replacementCount) + ' replacement(s) remaining';

            return {
                ...item,
                displayStatus,
                showManualReview,
                canReplace,
                showVersionTag,
                versionLabel,
                versionTagTitle,
                fileName: this.fileNameMap[item.Id] || null,
                recordUrl: '/' + item.Id,
                formattedDate: item.CreatedDate ? new Date(item.CreatedDate).toLocaleDateString() : '',
                badgeClass: 'badge ' + this.getBadgeClass(displayStatus)
            };

        });

    }

    handleManualReview(event) {

        this.selectedRecordId = event.currentTarget.dataset.id;

        this.showManualReviewModal = true;

    }

    handleModalClose() {

        this.showManualReviewModal = false;

        this.selectedRecordId = null;

    }

    handleReviewSuccess() {

        this.showManualReviewModal = false;
        this.selectedRecordId = null;

        refreshApex(this.wiredExistingResult)
            .catch(error => {
                console.error(error);
            });

    }

    getBadgeClass(status) {

        switch (status) {

            case 'Completed':
                return 'badge-completed';

            case 'Failed':
                return 'badge-failed';

            case 'Processing':
                return 'badge-processing';

            case 'Manual Review Required':
                return 'badge-review';

            case 'Submit for Approval':
                return 'badge-approval';

            default:
                return 'badge-queued';

        }

    }

    handleUploadFinished(event) {
        try {
            const files = event.detail.files;
            if (!files || files.length === 0) {
                this.showToast('Warning', 'No files were uploaded. Try again.', 'warning');
                return;
            }
            const newFiles = files.map((f) => ({ documentId: f.documentId, name: f.name }));
            this.uploadedFiles = [...this.uploadedFiles, ...newFiles];
            this.showToast('Success', `${files.length} file(s) uploaded successfully.`, 'success');
        } catch (err) {
            console.error('Upload handler error:', err);
            this.showToast('Error', 'Something went wrong reading the uploaded files.', 'error');
        }
    }

    handleProcessFiles() {
        if (this.uploadedFiles.length === 0) {
            this.showToast('Warning', 'Please upload at least one file first.', 'warning');
            return;
        }
        if (!this.recordId) {
            this.showToast('Error', 'Opportunity record context not found.', 'error');
            return;
        }

        this.isLoading = true;
        this.startLoadingMessageCycle();

        // Snapshot before clearing, so we can map recordId -> original file name
        const filesToProcess = [...this.uploadedFiles];
        const docIds = filesToProcess.map((f) => f.documentId);

        createLineItemsAndStartProcessing({
            opportunityId: this.recordId,
            contentDocumentIds: docIds
        })
            .then((resultIds) => {
                this.uploadedFiles = [];

                this.pollingFileNameMap = {};
                this.pollingMode = 'upload';
                this.pollingToastShown = {};
                resultIds.forEach((id, idx) => {
                    this.pollingFileNameMap[id] = filesToProcess[idx] ? filesToProcess[idx].name : 'File';
                });

                this.pollingRecordIds = resultIds;
                this.batchTotal = resultIds.length;
                this.batchCompletedCount = 0;

                this.showToast('Success', `Processing started for ${resultIds.length} file(s).`, 'success');

                this.startPolling();
            })
            .catch((error) => {
                this.stopLoadingMessageCycle();
                this.isLoading = false;
                console.error('Process Files error:', JSON.stringify(error));
                const message = error?.body?.message || error?.message || 'Something went wrong while processing files.';
                this.showToast('Error', message, 'error');
            });
    }

    handleRefreshClick() {
        const processingIds = this.existingItemsRaw
            .filter((item) => item.Status__c === 'Processing' || item.Status__c === 'Queued')
            .map((item) => item.Id);

        if (processingIds.length === 0) {
            this.showToast('Info', 'No files are currently processing.', 'info');
            return;
        }

        this.pollingMode = 'replacement';
        this.pollingRecordIds = processingIds;
        this.pollingToastShown = {};
        this.batchTotal = processingIds.length;
        this.batchCompletedCount = 0;

        this.isLoading = true;
        this.startLoadingMessageCycle();

        this.startPolling();
    }


    startPolling() {
        this.pollStatuses();
        this.pollTimer = setInterval(() => {
            this.pollStatuses();
        }, 3000);
    }

    pollStatuses() {
        if (this.isPolling) {
            return; // avoid overlapping calls if a poll runs long
        }
        this.isPolling = true;

        getLineItemStatuses({ recordIds: this.pollingRecordIds })
            .then((records) => {
                let completedCount = 0;

                records.forEach((rec) => {
                    if (this.isTerminalStatus(rec.Status__c)) {
                        completedCount++;

                        if (!this.pollingToastShown[rec.Id]) {
                            this.pollingToastShown[rec.Id] = true;
                            const fName = this.pollingFileNameMap[rec.Id] || this.fileNameMap[rec.Id] || rec.Name;

                            if (this.pollingMode === 'replacement') {
                                if (rec.Status__c === 'Failed') {
                                    this.showToast('Error', `Your replacement file could not be read - ${fName}`, 'error');
                                } else {
                                    this.showToast('Success', `Your replacement file read successfully- ${fName}`, 'success');
                                }
                            } else if (rec.Status__c === 'Failed') {
                                this.showToast('Error', `'${fName}' file processing failed.`, 'error');
                            } else {
                                this.showToast('Success', `'${fName}' file processing is completed.`, 'success');
                            }
                        }
                    }
                });

                this.batchCompletedCount = completedCount;

                if (completedCount === this.pollingRecordIds.length) {
                    this.stopPolling();
                    this.stopLoadingMessageCycle();
                    this.isLoading = false;
                    refreshApex(this.wiredExistingResult).catch((error) => console.error(error));
                }
            })
            .catch((error) => {
                console.error('Polling error:', error);
                this.stopPolling();
                this.stopLoadingMessageCycle();
                this.isLoading = false;
                this.showToast('Error', 'Something went wrong while checking file status. Please refresh to see the latest results.', 'error');
            })
            .finally(() => {
                this.isPolling = false;
            });
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    isTerminalStatus(status) {
        return status === 'Completed' || status === 'Manual Review Required' || status === 'Failed';
    }

    get batchProgressLabel() {
        if (this.batchTotal > 0) {
            return `${this.batchCompletedCount} of ${this.batchTotal} file(s) processed`;
        }
        return 'Submitting files…';
    }

    disconnectedCallback() {
        this.stopPolling();
        this.stopLoadingMessageCycle();
    }

    startLoadingMessageCycle() {
        let i = 0;
        this.loadingMessage = LOADING_MESSAGES[0];
        this.loadingTimer = setInterval(() => {
            i = (i + 1) % LOADING_MESSAGES.length;
            this.loadingMessage = LOADING_MESSAGES[i];
        }, 1400);
    }

    stopLoadingMessageCycle() {
        if (this.loadingTimer) {
            clearInterval(this.loadingTimer);
            this.loadingTimer = null;
        }
    }

    handleRemoveFile(event) {
        const idToRemove = event.currentTarget.dataset.id;
        this.uploadedFiles = this.uploadedFiles.filter((f) => f.documentId !== idToRemove);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: variant === 'error' ? 'sticky' : 'dismissable'
            })
        );
    }
}