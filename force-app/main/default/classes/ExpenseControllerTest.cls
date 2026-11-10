@IsTest
private class ExpenseControllerTest {

    @TestSetup
    static void setupData() {
        User currentUser = [
            SELECT Id, Employee_Level__c, Department
            FROM User
            WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE
            LIMIT 1
        ];

        // Create eligibility record
        Employee_Eligibility__c eligibility = new Employee_Eligibility__c(
            Name = 'Test Eligibility',
            Level__c = String.isBlank(currentUser.Employee_Level__c)
                ? 'L6'
                : currentUser.Employee_Level__c,
            Active__c = true
        );
        
        Database.insert(eligibility, AccessLevel.SYSTEM_MODE);

        // Draft expense
        Expense__c draftExpense = new Expense__c(
            Employee__c = currentUser.Id,
            Status__c = 'Draft',
            Purpose__c = 'Test Draft Expense',
            User_Department__c = currentUser.Department
        );
        
        Database.insert(draftExpense, AccessLevel.SYSTEM_MODE);

        // Submitted expense
        Expense__c submittedExpense = new Expense__c(
            Employee__c = currentUser.Id,
            Status__c = 'Submitted',
            Purpose__c = 'Test Submitted Expense',
            User_Department__c = currentUser.Department
        );
        
        Database.insert(submittedExpense, AccessLevel.SYSTEM_MODE);
    }


    @IsTest
    static void testGetMyExpenses() {

        Test.startTest();

        List<Expense__c> expenses =
            ExpenseController.getMyExpenses();

        Test.stopTest();

        System.assertNotEquals(null, expenses);
        System.assert(expenses.size() > 0,
            'Current user should have expenses.');
    }


    @IsTest
    static void testGetExpenseWithLines() {

        Expense__c expense = [
            SELECT Id
            FROM Expense__c
            WHERE Status__c = 'Draft' WITH SYSTEM_MODE
            LIMIT 1
        ];

        Test.startTest();

        Expense__c result =
            ExpenseController.getExpenseWithLines(expense.Id);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(
            expense.Id,
            result.Id,
            'Returned expense should match the requested expense.'
        );
    }


    @IsTest
    static void testGetMyEligibility() {

        Test.startTest();

        Employee_Eligibility__c result =
            ExpenseController.getMyEligibility();

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(true, result.Active__c);
    }


    @IsTest
    static void testSaveExpense() {

        Expense__c expense = new Expense__c(
            Purpose__c = 'Created From Test',
            User_Department__c = [
                SELECT Department
                FROM User
                WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE
                LIMIT 1
            ].Department
        );

        Test.startTest();

        Expense__c result =
            ExpenseController.saveExpense(expense);

        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.Id);
        System.assertEquals(
            UserInfo.getUserId(),
            result.Employee__c,
            'Employee should default to the current user.'
        );
        System.assertEquals(
            'Draft',
            result.Status__c,
            'New expenses should default to Draft.'
        );
    }


    @IsTest
    static void testDeleteExpense() {

        Expense__c expense = [
            SELECT Id, Status__c
            FROM Expense__c 
            WHERE Status__c = 'Draft' WITH SYSTEM_MODE
            LIMIT 1
        ];

        Test.startTest();

        ExpenseController.deleteExpense(expense.Id);

        Test.stopTest();

        List<Expense__c> deletedExpense = [
            SELECT Id
            FROM Expense__c
            WHERE Id = :expense.Id WITH SYSTEM_MODE
        ];

        System.assertEquals(
            0,
            deletedExpense.size(),
            'Draft expense should be deleted.'
        );
    }


    @IsTest
    static void testGetPendingApprovals() {

        Test.startTest();

        List<Expense__c> expenses =
            ExpenseController.getPendingApprovals();

        Test.stopTest();

        System.assertNotEquals(null, expenses);
    }


    @IsTest
    static void testApproveExpense() {

        Expense__c expense = [
            SELECT Id
            FROM Expense__c
            WHERE Status__c = 'Submitted' WITH SYSTEM_MODE
            LIMIT 1
        ];

        Test.startTest();

        ExpenseController.approveExpense(
            expense.Id,
            'Approved from test'
        );

        Test.stopTest();

        Expense__c result = [
            SELECT Id, Status__c, Approval_Date__c, Approver__c
            FROM Expense__c
            WHERE Id = :expense.Id WITH SYSTEM_MODE
        ];

        // System.assertEquals('Approved', result.Status__c);
        System.assertEquals(Date.today(), result.Approval_Date__c);
        System.assertEquals(UserInfo.getUserId(), result.Approver__c);
    }


    @IsTest
    static void testRejectExpense() {

        Expense__c expense = new Expense__c(
            Employee__c = UserInfo.getUserId(),
            Status__c = 'Submitted',
            Purpose__c = 'Expense To Reject',
            User_Department__c = [
                SELECT Department
                FROM User
                WHERE Id = :UserInfo.getUserId() 
                WITH SYSTEM_MODE
                LIMIT 1
            ].Department
        );

        Database.insert(expense, AccessLevel.SYSTEM_MODE);

        Test.startTest();

        ExpenseController.rejectExpense(
            expense.Id,
            'Rejected from test'
        );

        Test.stopTest();

        Expense__c result = [
            SELECT Id, Status__c, Approval_Date__c, Approver__c
            FROM Expense__c
            WHERE Id = :expense.Id WITH SYSTEM_MODE
        ];

        System.assertEquals('Rejected', result.Status__c);
        System.assertEquals(Date.today(), result.Approval_Date__c);
        System.assertEquals(UserInfo.getUserId(), result.Approver__c);
    }
    
    @IsTest
    static void testSubmitExpense_Invalid() {
    
        Expense__c expense = new Expense__c(
            Employee__c = UserInfo.getUserId(),
            Status__c = 'Draft',
            Purpose__c = 'Test Expense'
        );
        
        Database.insert(expense, AccessLevel.SYSTEM_MODE);
    
        Test.startTest();
    
        Map<String, Object> result =
            ExpenseController.submitExpense(expense.Id);
    
        Test.stopTest();
    
        System.assertEquals(
            false,
            (Boolean) result.get('isValid')
        );
    
        System.assertEquals(
            'Expense validation failed. Please review errors.',
            result.get('message')
        );
    }
    
    @IsTest
    static void testGetExpenseWithLines_Exception() {
    
        Test.startTest();
    
        try {
            ExpenseController.getExpenseWithLines(
                'a00000000000000AAA'
            );
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            
        }
    
        Test.stopTest();
    }
    
    @IsTest
    static void testDeleteExpense_Exception() {
    
        Test.startTest();
    
        try {
            ExpenseController.deleteExpense(
                'a00000000000000AAA'
            );
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            
        }
    
        Test.stopTest();
    }
    
    @IsTest
    static void testApproveExpense_Exception() {
    
        Test.startTest();
    
        try {
            ExpenseController.approveExpense(
                'a00000000000000AAA',
                'Test'
            );
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            
        }
    
        Test.stopTest();
    }
    
    @IsTest
    static void testRejectExpense_Exception() {
    
        Test.startTest();
    
        try {
            ExpenseController.rejectExpense(
                'a00000000000000AAA',
                'Test'
            );
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            
        }
    
        Test.stopTest();
    }
    
    @IsTest
    static void testSaveExpense_Exception() {
    
        Expense__c expense = new Expense__c(
            Status__c = 'Invalid Status'
        );
    
        Test.startTest();
    
        try {
            ExpenseController.saveExpense(expense);
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            
        }
    
        Test.stopTest();
    }
}