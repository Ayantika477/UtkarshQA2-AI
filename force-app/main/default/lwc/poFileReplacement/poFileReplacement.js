import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import reprocessLineItem from '@salesforce/apex/POLineItemController.reprocessLineItem';

const LOADING_MESSAGES = [
    'Reading document…',
    'Locating key fields…',
    'Extracting line items…',
    'Almost done…'
];

export default class PoFileReplacement extends LightningElement {
    @api recordId; // the PO_Line_Items__c Id being replaced

    stagedFile;
    isLoading = false;
    loadingMessage = LOADING_MESSAGES[0];
    loadingTimer;
    acceptedFormats = ['.pdf', '.jpg', '.jpeg', '.png'];

    get hasStagedFile() {
        return !!this.stagedFile;
    }

    get isProcessDisabled() {
        return !this.stagedFile || this.isLoading;
    }

    handleUploadFinished(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            this.stagedFile = { documentId: files[0].documentId, name: files[0].name };
        }
    }

    handleRemoveFile() {
        this.stagedFile = null;
    }

    handleProcessFile() {
        if (!this.stagedFile) {
            return;
        }

        this.isLoading = true;
        this.startLoadingMessageCycle();

        reprocessLineItem({
            recordId: this.recordId,
            contentDocumentId: this.stagedFile.documentId
        })
            .then(() => {
                this.stopLoadingMessageCycle();
                this.isLoading = false;
                this.showToast('Success', 'Reprocessing started. Updated details will appear shortly.', 'success');
                this.dispatchEvent(new CustomEvent('success', { detail: { recordId: this.recordId } }));
            })
            .catch((error) => {
                this.stopLoadingMessageCycle();
                this.isLoading = false;
                const message = error?.body?.message || error?.message || 'Something went wrong while reprocessing the file.';
                this.showToast('Error', message, 'error');
            });
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

    handleClose() {
        if (this.isLoading) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title, message, variant,
            mode: variant === 'error' ? 'sticky' : 'dismissable'
        }));
    }
}