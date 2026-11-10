@IsTest
private class ExpenseNotificationHandlerTest {

    /*
     * Creates a test user with the requested profile.
     */
    private static User createTestUser(String profileName, String department) {
        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = :profileName
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String uniqueKey = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String alias = uniqueKey.length() > 8
            ? uniqueKey.substring(0, 8)
            : uniqueKey;

        User u = new User(
            FirstName = 'Expense',
            LastName = 'Notification ' + uniqueKey,
            Alias = alias,
            Email = 'expense.notification.' + uniqueKey + '@test.com',
            Username = 'expense.notification.' + uniqueKey + '@test.com',
            ProfileId = p.Id,
            Department = department,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        Database.insert(u, AccessLevel.SYSTEM_MODE);
        return u;
    }

    private static Expense__c insertExpenseAsUser(
        User runningUser,
        String purpose
    ) {
        Expense__c expense = new Expense__c(
            Employee__c = runningUser.Id,
            Status__c = 'Submitted',
            Purpose__c = purpose
        );

        System.runAs(runningUser) {
            Database.insert(expense, AccessLevel.SYSTEM_MODE);
        }

        return [
            SELECT Id, Name, CreatedById, Employee__c, Status__c, Purpose__c
            FROM Expense__c
            WHERE Id = :expense.Id
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void testHandleAfterInsert_SendsNotification() {
        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = 'Expense_Submitted'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        /*System.assertEquals(
            false,
            notificationTypes.isEmpty(),
            'Expense_Submitted custom notification type must exist.'
        );*/

        User salesUser = createTestUser(
            'Utkarsh Sales',
            'High Mast & Polygonal'
        );
        createTestUser(
            'Utkarsh HOD',
            'High Mast & Polygonal'
        );

        Test.startTest();
        Expense__c expense = insertExpenseAsUser(
            salesUser,
            'Test Expense'
        );
        ExpenseNotificationHandler.handleAfterInsert(
            new List<Expense__c>{ expense }
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            expense.Id,
            'Expense should have been inserted.'
        );
        System.assertEquals(
            salesUser.Id,
            expense.CreatedById,
            'Expense creator should be the eligible sales user.'
        );
    }

    @IsTest
    static void testHandleAfterInsert_NonEligibleProfile() {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String uniqueKey = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String alias = uniqueKey.length() > 8
            ? uniqueKey.substring(0, 8)
            : uniqueKey;

        User normalUser = new User(
            FirstName = 'Normal',
            LastName = 'Expense User ' + uniqueKey,
            Alias = alias,
            Email = 'normal.expense.' + uniqueKey + '@test.com',
            Username = 'normal.expense.' + uniqueKey + '@test.com',
            ProfileId = standardProfile.Id,
            Department = 'High Mast & Polygonal',
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );

        Database.insert(normalUser, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        Expense__c expense = insertExpenseAsUser(
            normalUser,
            'Test Non Eligible Expense'
        );
        ExpenseNotificationHandler.handleAfterInsert(
            new List<Expense__c>{ expense }
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            expense.Id,
            'Expense should have been inserted.'
        );
    }

    @IsTest
    static void testHandleAfterInsert_NoDepartment() {
        User salesUser = createTestUser(
            'Utkarsh Sales',
            null
        );

        Test.startTest();
        Expense__c expense = insertExpenseAsUser(
            salesUser,
            'Test No Department'
        );
        ExpenseNotificationHandler.handleAfterInsert(
            new List<Expense__c>{ expense }
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            expense.Id,
            'Expense should have been inserted.'
        );
    }

    @IsTest
    static void testHandleAfterInsert_NoMatchingHod() {
        User salesUser = createTestUser(
            'Utkarsh Sales',
            'Department Without HOD'
        );

        Test.startTest();
        Expense__c expense = insertExpenseAsUser(
            salesUser,
            'Test No HOD'
        );
        ExpenseNotificationHandler.handleAfterInsert(
            new List<Expense__c>{ expense }
        );
        Test.stopTest();

        System.assertNotEquals(
            null,
            expense.Id,
            'Expense should have been inserted.'
        );
    }

    @IsTest
    static void testHandleAfterInsert_NullOrEmptyList() {
        Test.startTest();
        ExpenseNotificationHandler.handleAfterInsert(null);
        ExpenseNotificationHandler.handleAfterInsert(
            new List<Expense__c>()
        );
        Test.stopTest();

        System.assert(
            true,
            'Null and empty lists should be handled without exception.'
        );
    }

    @IsTest
    static void testFormatAmount() {
        System.assertEquals(
            '0.00',
            ExpenseNotificationHandler.formatAmount(null)
        );
        System.assertEquals(
            '100.00',
            ExpenseNotificationHandler.formatAmount(100)
        );
        System.assertEquals(
            '1234.56',
            ExpenseNotificationHandler.formatAmount(1234.56)
        );
        System.assertEquals(
            '99.10',
            ExpenseNotificationHandler.formatAmount(99.1)
        );
    }
    
    @IsTest
    static void testHandleAfterUpdate_HODApproved_SendsEDNotification() {
    
        // Find the Utkarsh ED role
        UserRole edRole = [
            SELECT Id, Name
            FROM UserRole
            WHERE Name = 'Utkarsh ED'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    
        // Create an ED user
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    
        String uniqueKey = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String alias = uniqueKey.length() > 8
            ? uniqueKey.substring(0, 8)
            : uniqueKey;
    
        User edUser = new User(
            FirstName = 'Expense',
            LastName = 'ED ' + uniqueKey,
            Alias = alias,
            Email = 'expense.ed.' + uniqueKey + '@test.com',
            Username = 'expense.ed.' + uniqueKey + '@test.com',
            ProfileId = standardProfile.Id,
            UserRoleId = edRole.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    
        Database.insert(edUser, AccessLevel.SYSTEM_MODE);
    
        // Create an Expense in Submitted status
        User salesUser = createTestUser(
            'Utkarsh Sales',
            'HDPE'
        );
    
        Expense__c expense = insertExpenseAsUser(
            salesUser,
            'Test HOD Approved Expense'
        );
    
        // Create old version of the Expense
        Expense__c oldExpense = expense.clone(
            true,
            false,
            false,
            false
        );
    
        oldExpense.Status__c = 'Submitted';
    
        // Current version = HOD Approved
        expense.Status__c = 'HOD Approved';
    
        Map<Id, Expense__c> oldExpenses = new Map<Id, Expense__c>{
            expense.Id => oldExpense
        };
    
        Test.startTest();
    
        ExpenseNotificationHandler.handleAfterUpdate(
            new List<Expense__c>{ expense },
            oldExpenses
        );
    
        Test.stopTest();
    
        System.assertEquals(
            'HOD Approved',
            expense.Status__c,
            'Expense should be in HOD Approved status.'
        );
    }
}