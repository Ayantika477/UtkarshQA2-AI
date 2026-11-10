public without sharing class bidderAwardController {

    /** Type and search on Account Name. */
    @AuraEnabled(cacheable=true)
    public static String getBidderName(Id opportunityId) {
    Opportunity opp = [
        SELECT Bidder__r.Name
        FROM Opportunity
        WHERE Id = :opportunityId
        WITH USER_MODE
        LIMIT 1
    ];
    return opp.Bidder__r != null ? opp.Bidder__r.Name : null;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchKey) {
        if (String.isBlank(searchKey) || searchKey.trim().length() < 2) {
            return new List<Account>();
        }
        String key = '%' + String.escapeSingleQuotes(searchKey.trim()) + '%';
        return [
            SELECT Id, Name, Phone, Email__c, BillingCity
            FROM Account
            WHERE Name LIKE :key
            WITH SYSTEM_MODE
            ORDER BY Name ASC
            LIMIT 10
        ];
    }

    /**
     * Duplicate detection: exact Phone OR exact Email__c OR fuzzy Name.
     */
    @AuraEnabled
    public static List<Account> findDuplicateAccounts(String companyName, String phone, String email) {
        Account candidate = new Account(
            Name    = companyName,
            Phone   = phone,
            Email__c = email
        );

        List<Datacloud.FindDuplicatesResult> fdResults =
            Datacloud.FindDuplicates.findDuplicates(new List<Account>{ candidate });

        Set<Id> candidateIds = new Set<Id>();
        for (Datacloud.FindDuplicatesResult fdr : fdResults) {
            for (Datacloud.DuplicateResult dr : fdr.getDuplicateResults()) {
                for (Datacloud.MatchResult mr : dr.getMatchResults()) {
                    for (Datacloud.MatchRecord rec : mr.getMatchRecords()) {
                        candidateIds.add(rec.getRecord().Id);
                    }
                }
            }
        }

        if (candidateIds.isEmpty()) {
            return new List<Account>();
        }

        Map<Id, Account> candidates = new Map<Id, Account>([
            SELECT Id, Name, Phone, Email__c
            FROM Account
            WHERE Id IN :candidateIds
            WITH SYSTEM_MODE
        ]);

        List<Account> matches = new List<Account>();
        for (Account a : candidates.values()) {
            Boolean phoneMatch = String.isNotBlank(phone) && phone == a.Phone;
            Boolean emailMatch = String.isNotBlank(email) && email == a.Email__c;
            Boolean nameFuzzy  = String.isNotBlank(companyName) && a.Name != null
                && companyName.toLowerCase().contains(a.Name.toLowerCase().left(4));
            if (phoneMatch || emailMatch || nameFuzzy) {
                matches.add(a);
            }
        }
        return matches;
    }

    /** Fetch existing contacts for a selected Account */
    @AuraEnabled
    public static List<Contact> getAccountContacts(Id accountId) {
        return [
            SELECT Id, Name, Email, Phone 
            FROM Contact 
            WHERE AccountId = :accountId 
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
    }

    /** Fetch Bidder Contact Details related to the Opportunity */
    @AuraEnabled(cacheable=true)
    public static Bidders_Contact_Details__c getBidderContactDetails(Id opportunityId) {
        // First get the Bidder ID from the Opportunity
        Opportunity opp = [SELECT Bidder__c FROM Opportunity WHERE Id = :opportunityId WITH USER_MODE LIMIT 1];
        
        if (opp.Bidder__c != null) {
            // Then get the related Bidder Contact Details
            List<Bidders_Contact_Details__c> details = [
                SELECT Name, Contact_Number__c, Email__c,Bidders__r.Name
                FROM Bidders_Contact_Details__c 
                WHERE Bidders__c = :opp.Bidder__c 
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            
            if (!details.isEmpty()) {
                return details[0];
            }
        }
        return null;
    }

    /**
     * Finalizes the Award process:
     * 1. Changes the awarded Opp to 'Master_Opportunity' Record Type
     * 2. Marks the Parent Opp and all sibling Opps as Closed Lost with reason 'Tender lost'
     */
    @AuraEnabled
    public static void finalizeOpportunityAward(Id awardedOppId) {
        // 1. Get the Awarded Opp and its parent
        Opportunity awardedOpp = [
            SELECT Id, Parent_Opportunity__c, ownerId, Department_NameFormula__c
            FROM Opportunity 
            WHERE Id = :awardedOppId 
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        // 2. Get the 'Master_Opportunity' Record Type ID
        Id masterRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                                      .get('Master_Opportunity').getRecordTypeId();

        // 3. Prepare the list of Opportunities to update
        List<Opportunity> oppsToUpdate = new List<Opportunity>();
        Set<Id> oppListIds = new Set<Id>();

        // Update the Awarded Opp's Record Type
        awardedOpp.RecordTypeId = masterRecordTypeId;
        oppsToUpdate.add(awardedOpp);
        oppListIds.add(awardedOpp.Id);

        // 4. If there is a parent, close it and all of its OTHER children
        if (awardedOpp.Parent_Opportunity__c != null) {
            
            // Query the Parent and Sibling Opportunities (excluding the Awarded Opp)
            List<Opportunity> relatedOpps = [
                SELECT Id 
                FROM Opportunity 
                WHERE Id = :awardedOpp.Parent_Opportunity__c 
                   OR (Parent_Opportunity__c = :awardedOpp.Parent_Opportunity__c AND Id != :awardedOppId)
                   WITH SYSTEM_MODE
            ];

            for (Opportunity opp : relatedOpps) {
                opp.StageName = 'Closed Lost'; 
                opp.Lost_Reason__c = 'Tender lost';
                oppsToUpdate.add(opp);
                oppListIds.add(opp.Id);
            }
        }

        // 5. Perform the bulk update
        if (!oppsToUpdate.isEmpty()) {
            // Using SYSTEM_MODE to ensure we can update related records without stopping due to field-level security
            Database.update(oppsToUpdate, AccessLevel.SYSTEM_MODE); 
        }

        //close all related tasks
        handleRelatedTasks(oppListIds, awardedOppId, awardedOpp.ownerId);

        // 6. Send the push notification
        sendAwardNotification(awardedOpp);

    }

    private static void sendAwardNotification(Opportunity awardedOpp) {
        Set<String> recipientIds = new Set<String>();
        
        // Add the Opportunity Owner
        if (awardedOpp.OwnerId != null) {
            recipientIds.add(awardedOpp.OwnerId);
        }

        // Query active users with the matching profiles and department
        if (String.isNotBlank(awardedOpp.Department_NameFormula__c)) {
            List<User> matchingUsers = [
                SELECT Id 
                FROM User 
                WHERE Profile.Name IN ('CRM Head', 'Utkarsh HOD') 
                  AND Department = :awardedOpp.Department_NameFormula__c
                  AND IsActive = true
                WITH SYSTEM_MODE
            ];
            
            for (User u : matchingUsers) {
                recipientIds.add(u.Id);
            }
        } else {
            throw new AuraHandledException('Cannot send notifications. Department name is blank in the awarded opportunity.');
        }

        // Exit if no valid recipients are found
        if (recipientIds.isEmpty()) {
            return;
        }

        try {
            // Retrieve the Custom Notification Type
            CustomNotificationType notificationType = [
                SELECT Id 
                FROM CustomNotificationType 
                WHERE DeveloperName = 'L1_Bidder_Notification' 
                LIMIT 1
            ];

            // Configure and send the notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('L1 Bidder Declared');
            notification.setBody('L1 Bidder declared. Opportunity is ready for confirmation.');
            notification.setNotificationTypeId(notificationType.Id);
            notification.setTargetId(awardedOpp.Id); // Clicking the notification directs the user to the Opportunity record
            
            notification.send(recipientIds);
            
        } catch (Exception e) {
            System.debug('Failed to send Custom Notification: ' + e.getMessage());
        }
    }

    public static void handleRelatedTasks(Set<Id> allAffectedOppIds, Id awardedOppId, Id ownerId) {

        if(allAffectedOppIds.isEmpty()){
            throw new AuraHandledException('Opportunity ids are empty for closing task');
        }
        if(awardedOppId == null){
            throw new AuraHandledException('Awarded opportunity id is empty for closing task');
        }
        if(ownerId == null){
            throw new AuraHandledException('Awarded opportunity owner is empty for closing task');
        }

        // 1. Query and close all open Tasks related to the affected Opportunities
        List<Task> tasksToClose = [
            SELECT Id, Status 
            FROM Task 
            WHERE WhatId IN :allAffectedOppIds 
              AND IsClosed = false 
            WITH SYSTEM_MODE
        ];
        
        for (Task t : tasksToClose) {
            t.Status = 'Completed'; 
        }

        if (!tasksToClose.isEmpty()) {
            Database.update(tasksToClose, AccessLevel.SYSTEM_MODE);
        }

        // 2. Create new Task based on Flow criteria from image_d17e8b.png
        Task newFollowUpTask = new Task(
            Subject = 'Call Customer - New Opportunity Created',
            TaskSubtype = 'Call',
            OwnerId = ownerId,
            WhatId = awardedOppId,
            Status = 'Nurture' // Mapped from the "Stage" field in the reference image
        );

        // Time-based Description and Follow_Up_Date_Time__c Logic
        Datetime nowTime = Datetime.now();
        if (nowTime.hour() < 14) {
            // Before 2 PM Local Time -> Call at 5 PM Today
            newFollowUpTask.Description = 'An opportunity has been created , make sure to call at 5PM';
            newFollowUpTask.Follow_Up_Date_Time__c = Datetime.newInstance(nowTime.date(), Time.newInstance(17, 0, 0, 0));
        } else {
            // After 2 PM Local Time -> Call at 10 AM Tomorrow
            newFollowUpTask.Description = 'An opportunity has been created , make sure to call at 10AM tomorrow';
            newFollowUpTask.Follow_Up_Date_Time__c = Datetime.newInstance(nowTime.date().addDays(1), Time.newInstance(10, 0, 0, 0));
        }

        Database.insert(newFollowUpTask, AccessLevel.SYSTEM_MODE);
    }

    @AuraEnabled
    public static Id createAddressBookAndJunction(Id accountId, Id opportunityId, Map<String, Object> addressData) {
    if (addressData == null || addressData.isEmpty()) {
        return null;
    }

    // Build the Address Book record from the map
    Address_Book__c ab = new Address_Book__c();          // <-- confirm object API name
    ab.Account__c      = accountId;                        // <-- confirm lookup field name
    if (addressData.containsKey('Street__c'))  ab.Street__c  = (String) addressData.get('Street__c');
    if (addressData.containsKey('City__c'))    ab.City__c    = (String) addressData.get('City__c');
    if (addressData.containsKey('State__c'))   ab.State__c   = (String) addressData.get('State__c');
    if (addressData.containsKey('Country__c')) ab.Country__c = (String) addressData.get('Country__c');
    if (addressData.containsKey('PIN__c'))     ab.PIN__c     = (String) addressData.get('PIN__c');
    if (addressData.containsKey('Zone__c'))    ab.Zone__c    = (String) addressData.get('Zone__c');
    if (addressData.containsKey('Primary_Address__c')) {
        ab.Primary_Address__c = (Boolean) addressData.get('Primary_Address__c');
    }
    
    insert as system ab;

    // Create the junction record linking Address Book <-> Opportunity
    Opportunity_Address_Junc__c junc = new Opportunity_Address_Junc__c(
        Opportunity__c   = opportunityId,   // <-- confirm field name
        Address_Book__c  = ab.Id            // <-- confirm field name
    );
    insert as system junc;

    return ab.Id;
}

    @AuraEnabled(cacheable=true)
    public static String getOpportunityDepartment(Id opportunityId) {
        Opportunity opp = [
            SELECT Department_Name__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];

        return opp.Department_Name__c;
    }

    @AuraEnabled
    public static void createProductCategories(List<Product_Category__c> productCategories) {
        if (productCategories == null || productCategories.isEmpty()) {
            return;
        }

        insert as system productCategories;
    }
}