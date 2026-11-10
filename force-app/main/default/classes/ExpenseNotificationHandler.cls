public without sharing class ExpenseNotificationHandler {

    // Profiles whose expense creation should trigger an HOD notification
    private static final Set<String> NOTIFICATION_PROFILES = new Set<String>{
        'Utkarsh Sales',
        'CRM Head',
        'Utkarsh CRM',
        'Utkarsh Tender',
        'Utakrsh Department CRM User'
    };

    // HOD profile
    private static final String HOD_PROFILE = 'Utkarsh HOD';

    // ED role
    private static final String ED_ROLE = 'Utkarsh ED';

    // Expense statuses
    private static final String SUBMITTED_STATUS = 'Submitted';
    private static final String HOD_APPROVED_STATUS = 'HOD Approved';

    // Custom Notification Type DeveloperName
    private static final String NOTIFICATION_TYPE = 'Expense_Submitted';


    /**
     * Called after Expense__c insert.
     *
     * If the Expense is in Submitted status and was created by a user
     * belonging to one of the configured profiles, notify the HOD
     * belonging to the creator's department.
     */
    public static void handleAfterInsert(List<Expense__c> expenses) {

        if (expenses == null || expenses.isEmpty()) {
            return;
        }

        Set<Id> creatorIds = new Set<Id>();

        // Get creators of the newly created expenses
        for (Expense__c expense : expenses) {

            // Only Submitted expenses should trigger HOD notification
            if (expense.Status__c != SUBMITTED_STATUS) {
                continue;
            }

            if (expense.CreatedById != null) {
                creatorIds.add(expense.CreatedById);
            }
        }

        if (creatorIds.isEmpty()) {
            return;
        }

        // Get creator details
        Map<Id, User> creatorsById = new Map<Id, User>([
            SELECT Id, Name, Department, Profile.Name
            FROM User
            WHERE Id IN :creatorIds
            WITH SYSTEM_MODE
        ]);

        // Get relevant departments
        Set<String> departments = new Set<String>();

        for (Expense__c expense : expenses) {

            if (expense.Status__c != SUBMITTED_STATUS) {
                continue;
            }

            User creator = creatorsById.get(expense.CreatedById);

            if (creator == null) {
                continue;
            }

            if (!NOTIFICATION_PROFILES.contains(creator.Profile.Name)) {
                continue;
            }

            if (String.isBlank(creator.Department)) {
                continue;
            }

            departments.add(creator.Department);
        }

        if (departments.isEmpty()) {
            return;
        }

        // Find active HODs for the relevant departments
        Map<String, User> hodByDepartment = new Map<String, User>();

        for (User hod : [
            SELECT Id, Name, Department, Profile.Name
            FROM User
            WHERE IsActive = true
            AND Department IN :departments
            AND Profile.Name = :HOD_PROFILE
            WITH SYSTEM_MODE
        ]) {
            hodByDepartment.put(hod.Department, hod);
        }

        if (hodByDepartment.isEmpty()) {
            return;
        }

        Id notificationTypeId = getNotificationTypeId();

        if (notificationTypeId == null) {
            return;
        }

        // Send HOD notifications
        for (Expense__c expense : expenses) {

            if (expense.Status__c != SUBMITTED_STATUS) {
                continue;
            }

            User creator = creatorsById.get(expense.CreatedById);

            if (creator == null ||
                !NOTIFICATION_PROFILES.contains(creator.Profile.Name) ||
                String.isBlank(creator.Department)) {
                continue;
            }

            User hod = hodByDepartment.get(creator.Department);

            if (hod == null) {
                continue;
            }

            sendHODNotification(
                expense,
                creator,
                hod.Id,
                notificationTypeId
            );
        }
    }


    /**
     * Called after Expense__c update.
     *
     * If the Expense status changes to HOD Approved,
     * notify the Utkarsh ED user(s).
     */
    public static void handleAfterUpdate(List<Expense__c> expenses, Map<Id, Expense__c> oldExpenses) {

        if (expenses == null || expenses.isEmpty() || oldExpenses == null) {
            return;
        }

        Set<Id> approvedExpenseIds = new Set<Id>();

        for (Expense__c expense : expenses) {

            Expense__c oldExpense = oldExpenses.get(expense.Id);

            if (oldExpense == null) {
                continue;
            }

            // Only notify ED when the status actually changes
            // to HOD Approved.
            if (expense.Status__c == HOD_APPROVED_STATUS &&
                oldExpense.Status__c != HOD_APPROVED_STATUS) {

                approvedExpenseIds.add(expense.Id);
            }
        }

        if (approvedExpenseIds.isEmpty()) {
            return;
        }

        // Get ED users
        Set<String> edUserIds = new Set<String>();

        for (User edUser : [
            SELECT Id
            FROM User
            WHERE IsActive = true
            AND UserRole.Name = :ED_ROLE
            WITH SYSTEM_MODE
        ]) {
            edUserIds.add(edUser.Id);
        }

        if (edUserIds.isEmpty()) {
            return;
        }

        Id notificationTypeId = getNotificationTypeId();

        if (notificationTypeId == null) {
            return;
        }

        // Get approved expenses
        Map<Id, Expense__c> approvedExpensesById = new Map<Id, Expense__c>([
            SELECT Id, Name, Status__c
            FROM Expense__c
            WHERE Id IN :approvedExpenseIds
            WITH SYSTEM_MODE
        ]);

        // Send notification for each HOD-approved expense
        for (Expense__c expense : approvedExpensesById.values()) {

            sendEDNotification(
                expense,
                edUserIds,
                notificationTypeId
            );
        }
    }


    /**
     * Sends notification to the HOD.
     */
    public static void sendHODNotification(Expense__c expense, User creator, Id hodUserId, Id notificationTypeId) {

        Messaging.CustomNotification notification =
            new Messaging.CustomNotification();

        notification.setNotificationTypeId(notificationTypeId);

        notification.setTitle('New Expense Submitted');

        notification.setBody(
            creator.Name +
            ' has submitted an expense ' +
            expense.Name +
            '. Click to view.'
        );

        // Clicking the notification opens the Expense record
        notification.setTargetId(expense.Id);

        notification.send(new Set<String>{ hodUserId });
    }


    /**
     * Sends notification to all active users whose role is Utkarsh ED.
     */
    public static void sendEDNotification(Expense__c expense, Set<String> edUserIds, Id notificationTypeId) {

        Messaging.CustomNotification notification =
            new Messaging.CustomNotification();

        notification.setNotificationTypeId(notificationTypeId);

        notification.setTitle('Expense Approved by HOD');

        notification.setBody(
            'Expense ' +
            expense.Name +
            ' has been approved by the HOD. Click to view.'
        );

        // Clicking the notification opens the Expense record
        notification.setTargetId(expense.Id);

        notification.send(edUserIds);
    }


    /**
     * Gets the Custom Notification Type Id.
     */
    public static Id getNotificationTypeId() {

        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :NOTIFICATION_TYPE
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (notificationTypes.isEmpty()) {
            return null;
        }

        return notificationTypes[0].Id;
    }


    /**
     * Formats an amount to two decimal places.
     */
    public static String formatAmount(Decimal amount) {

        if (amount == null) {
            return '0.00';
        }

        return String.valueOf(amount.setScale(2));
    }
}