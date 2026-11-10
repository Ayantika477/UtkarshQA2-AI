public with sharing class POLineItemController {

    @AuraEnabled
    public static List<Id> createLineItemsAndStartProcessing(Id opportunityId, List<Id> contentDocumentIds) {
        try {
            List<PO_Line_Items__c> newRecords = new List<PO_Line_Items__c>();
            Map<Id, PO_Line_Items__c> docIdToRecord = new Map<Id, PO_Line_Items__c>();

            for (Id docId : contentDocumentIds) {
                PO_Line_Items__c rec = new PO_Line_Items__c(
                    Opportunity__c = opportunityId,
                    Status__c = 'Queued'
                );
                newRecords.add(rec);
                docIdToRecord.put(docId, rec);
            }

            insert newRecords;

            // Link files to records via ContentDocumentLink
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            Integer i = 0;
            List<Id> docIdList = new List<Id>(docIdToRecord.keySet());
            for (Id docId : docIdList) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = docId,
                    LinkedEntityId = newRecords[i].Id,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                ));
                i++;
            }
            insert links;

            // Build ordered list of record Ids + their ContentDocumentId for queueable chain
            List<POQueueableProcessor.FileJob> jobs = new List<POQueueableProcessor.FileJob>();
            i = 0;
            for (Id docId : docIdList) {
                POQueueableProcessor.FileJob job = new POQueueableProcessor.FileJob();
                job.recordId = newRecords[i].Id;
                job.contentDocumentId = docId;
                jobs.add(job);
                i++;
            }

            // Start the chain
            System.enqueueJob(new POQueueableProcessor(jobs, 0));

            List<Id> resultIds = new List<Id>();
            for (PO_Line_Items__c r : newRecords) {
                resultIds.add(r.Id);
            }
            return resultIds;

        } catch (Exception e) {
            throw new AuraHandledException('Error creating records: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<PO_Line_Items__c> getLineItemStatuses(List<Id> recordIds) {
        return [
            SELECT Id, Name, Status__c, PO_Number__c, Approval_Status__c ,Manual_Review_Completed__c ,Error_Message__c
            FROM PO_Line_Items__c
            WHERE Id IN :recordIds
        ];
    }

    @AuraEnabled(cacheable=true)
public static List<PO_Line_Items__c> getExistingLineItems(Id opportunityId) {
    return [
        SELECT Id, Name, Status__c, PO_Number__c, PO_Date__c, Amount__c,
               Manual_Review_Completed__c, Approval_Status__c, CreatedDate,
               PO_revision_Number__c, PO_File_History__c
        FROM PO_Line_Items__c
        WHERE Opportunity__c = :opportunityId
        ORDER BY CreatedDate DESC
    ];
}

@AuraEnabled(cacheable=true)
public static Map<Id, String> getFileNamesForRecords(List<Id> recordIds) {

    Map<Id, String> fileNameMap = new Map<Id, String>();

    if (recordIds == null || recordIds.isEmpty()) {
        return fileNameMap;
    }

    List<ContentDocumentLink> links = [
        SELECT ContentDocumentId, LinkedEntityId
        FROM ContentDocumentLink
        WHERE LinkedEntityId IN :recordIds
    ];

    if (links.isEmpty()) {
        return fileNameMap;
    }

    Map<Id, Id> docToRecord = new Map<Id, Id>();
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink l : links) {
        docToRecord.put(l.ContentDocumentId, l.LinkedEntityId);
        docIds.add(l.ContentDocumentId);
    }

    List<ContentVersion> versions = [
        SELECT ContentDocumentId, Title, CreatedDate
        FROM ContentVersion
        WHERE ContentDocumentId IN :docIds
        AND IsLatest = true
        ORDER BY CreatedDate DESC
    ];

    // If a record has more than one linked file (original + replaced),
    // this keeps the most recently uploaded one, since versions is already
    // ordered newest-first and containsKey blocks any later overwrite.
    for (ContentVersion cv : versions) {
        Id recId = docToRecord.get(cv.ContentDocumentId);
        if (recId != null && !fileNameMap.containsKey(recId)) {
            fileNameMap.put(recId, cv.Title);
        }
    }

    return fileNameMap;
}

@AuraEnabled
public static Id reprocessLineItem(Id recordId, Id contentDocumentId) {
    try {
        if (recordId == null || contentDocumentId == null) {
            throw new AuraHandledException('Record Id and File are required.');
        }

        if (!Schema.sObjectType.PO_Line_Items__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to update this record.');
        }

        PO_Line_Items__c existingRecord = [
            SELECT Id, Status__c, PO_revision_Number__c, PO_File_History__c
            FROM PO_Line_Items__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (existingRecord.Status__c != 'Completed' && existingRecord.Status__c != 'Failed') {
    throw new AuraHandledException('Only completed or failed PO records can be replaced.');
}

        Integer currentVersion = existingRecord.PO_revision_Number__c == null
            ? 1
            : Integer.valueOf(existingRecord.PO_revision_Number__c);

        if (currentVersion >= 5) {
            throw new AuraHandledException('This PO has already been replaced the maximum number of times (4) and cannot be replaced again.');
        }

        Integer newVersion = currentVersion + 1;

        // Find the file being replaced: most recent file already linked, excluding the new upload
        String oldFileName;
        List<ContentDocumentLink> oldLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocumentId != :contentDocumentId
        ];

        if (!oldLinks.isEmpty()) {
            Set<Id> oldDocIds = new Set<Id>();
            for (ContentDocumentLink l : oldLinks) {
                oldDocIds.add(l.ContentDocumentId);
            }

            List<ContentVersion> oldVersions = [
                SELECT Title
                FROM ContentVersion
                WHERE ContentDocumentId IN :oldDocIds
                AND IsLatest = true
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!oldVersions.isEmpty()) {
                oldFileName = oldVersions[0].Title;
            }
        }

        // Name of the newly uploaded file
        String newFileName;
        List<ContentVersion> newVersions = [
            SELECT Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if (!newVersions.isEmpty()) {
            newFileName = newVersions[0].Title;
        }

        String historyLine =
            'v' + newVersion + ': "' +
            (oldFileName == null ? 'previous file' : oldFileName) +
            '" replaced with "' +
            (newFileName == null ? 'new file' : newFileName) +
            '" on ' + System.now().format('dd-MMM-yyyy hh:mm a');

        String updatedHistory = String.isBlank(existingRecord.PO_File_History__c)
            ? historyLine
            : existingRecord.PO_File_History__c + '\n' + historyLine;

        PO_Line_Items__c updateRec = new PO_Line_Items__c(
            Id = recordId,
            PO_revision_Number__c = newVersion,
            PO_File_History__c = updatedHistory,
            Status__c = 'Processing',
            Error_Message__c = null,
            Manual_Review_Completed__c = false,   // reset stale review flag
            Approval_Status__c = null,            // reset stale approval flag
            Sent_For_Approval__c = false
        );

        update updateRec;

        POQueueableProcessor.FileJob job = new POQueueableProcessor.FileJob();
        job.recordId = recordId;
        job.contentDocumentId = contentDocumentId;

        System.enqueueJob(
            new POQueueableProcessor(
                new List<POQueueableProcessor.FileJob>{ job },
                0
            )
        );

        return recordId;

    } catch (AuraHandledException ahe) {
        throw ahe; // preserve the original message — see note below
    } catch (Exception e) {
        throw new AuraHandledException('Error starting reprocessing: ' + e.getMessage());
    }
}
}