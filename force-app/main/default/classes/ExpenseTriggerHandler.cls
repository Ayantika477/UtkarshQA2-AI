/**
 * @description Trigger handler for Expense__c object
 * Handles trigger logic following the trigger handler pattern
 * @author Salesforce
 * @date 2026
 */
public with sharing class ExpenseTriggerHandler {
    
    /**
     * @description Before Insert trigger logic
     * @param newExpenses List of new expense records
     */
    public static void beforeInsert(List<Expense__c> newExpenses) {
        // Set default values
        for (Expense__c expense : newExpenses) {
            if (String.isBlank(expense.Status__c)) {
                expense.Status__c = 'Draft';
            }
            
            if (expense.Employee__c == null) {
                expense.Employee__c = UserInfo.getUserId();
            }
        }
    }
    
    /**
     * @description Before Update trigger logic
     * @param newExpenses List of updated expense records
     * @param oldExpensesMap Map of old expense records
     */
    public static void beforeUpdate(List<Expense__c> newExpenses, Map<Id, Expense__c> oldExpensesMap) {
        // Validate status transitions
        for (Expense__c expense : newExpenses) {
            Expense__c oldExpense = oldExpensesMap.get(expense.Id);
            
            // Prevent modification of approved/reimbursed expenses
            if ((oldExpense.Status__c == 'Approved' || oldExpense.Status__c == 'Reimbursed') &&
                expense.Status__c != oldExpense.Status__c &&
                expense.Status__c != 'Reimbursed') {
                expense.addError('Cannot modify an approved expense');
            }
            
            // Set submitted date when status changes to Submitted
            if (expense.Status__c == 'Submitted' && oldExpense.Status__c != 'Submitted') {
                expense.Submitted_Date__c = Date.today();
            }
            
            // Set approval date when status changes to Approved
            if (expense.Status__c == 'Approved' && oldExpense.Status__c != 'Approved') {
                expense.Approval_Date__c = Date.today();
                if (expense.Approver__c == null) {
                    expense.Approver__c = UserInfo.getUserId();
                }
            }
        }
    }
    
    /**
     * @description After Insert trigger logic
     * @param newExpenses List of new expense records
     */
    public static void afterInsert(List<Expense__c> newExpenses) {
        // Future: Send notifications, create chatter posts, etc.
    }
    
    /**
     * @description After Update trigger logic
     * @param newExpenses List of updated expense records
     * @param oldExpensesMap Map of old expense records
     */
    public static void afterUpdate(List<Expense__c> newExpenses, Map<Id, Expense__c> oldExpensesMap) {
        List<Id> submittedExpenseIds = new List<Id>();
        List<Id> approvedExpenseIds = new List<Id>();
        List<Id> rejectedExpenseIds = new List<Id>();
        
        // Collect expenses that changed status
        for (Expense__c expense : newExpenses) {
            Expense__c oldExpense = oldExpensesMap.get(expense.Id);
            
            if (expense.Status__c == 'Submitted' && oldExpense.Status__c != 'Submitted') {
                submittedExpenseIds.add(expense.Id);
            } else if (expense.Status__c == 'Approved' && oldExpense.Status__c != 'Approved') {
                approvedExpenseIds.add(expense.Id);
            } else if (expense.Status__c == 'Rejected' && oldExpense.Status__c != 'Rejected') {
                rejectedExpenseIds.add(expense.Id);
            }
        }
        
        // Send notifications for status changes
        if (!submittedExpenseIds.isEmpty()) {
            sendSubmissionNotifications(submittedExpenseIds);
        }
        
        if (!approvedExpenseIds.isEmpty()) {
            sendApprovalNotifications(approvedExpenseIds);
        }
        
        if (!rejectedExpenseIds.isEmpty()) {
            sendRejectionNotifications(rejectedExpenseIds);
        }
    }
    
    /**
     * @description Before Delete trigger logic
     * @param oldExpenses List of expenses being deleted
     */
    public static void beforeDelete(List<Expense__c> oldExpenses) {
        // Prevent deletion of submitted or approved expenses
        for (Expense__c expense : oldExpenses) {
            if (expense.Status__c != 'Draft') {
                expense.addError('Only Draft expenses can be deleted');
            }
        }
    }
    
    /**
     * @description Sends submission notifications to approvers
     * @param expenseIds List of submitted expense IDs
     */
    private static void sendSubmissionNotifications(List<Id> expenseIds) {
        // Future: Implement email/chatter notifications to managers
        // For now, just log the submission
        System.debug('Expenses submitted for approval: ' + expenseIds);
    }
    
    /**
     * @description Sends approval notifications to employees
     * @param expenseIds List of approved expense IDs
     */
    private static void sendApprovalNotifications(List<Id> expenseIds) {
        // Future: Implement email/chatter notifications to employees
        System.debug('Expenses approved: ' + expenseIds);
    }
    
    /**
     * @description Sends rejection notifications to employees
     * @param expenseIds List of rejected expense IDs
     */
    private static void sendRejectionNotifications(List<Id> expenseIds) {
        // Future: Implement email/chatter notifications to employees
        System.debug('Expenses rejected: ' + expenseIds);
    }
}