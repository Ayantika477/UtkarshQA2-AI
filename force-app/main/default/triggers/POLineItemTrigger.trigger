trigger POLineItemTrigger on PO_Line_Items__c (after update) {

    System.debug('===== POLineItemTrigger Fired =====');

    Set<Id> oppIds = new Set<Id>();

    for (PO_Line_Items__c rec : Trigger.new) {

        PO_Line_Items__c oldRec = Trigger.oldMap.get(rec.Id);

        System.debug('Old Approval = ' + oldRec.Approval_Status__c);
        System.debug('New Approval = ' + rec.Approval_Status__c);

        if (rec.Approval_Status__c == 'Approved'
            && oldRec.Approval_Status__c != 'Approved') {

            System.debug('Adding Opportunity : ' + rec.Opportunity__c);

            if (rec.Opportunity__c != null) {
                oppIds.add(rec.Opportunity__c);
            }
        }
    }

    System.debug('OppIds = ' + oppIds);

    if (!oppIds.isEmpty()) {
        OrderSyncService.syncOrders(oppIds);
    }
}