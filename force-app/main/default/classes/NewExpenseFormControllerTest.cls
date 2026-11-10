@isTest
private class NewExpenseFormControllerTest {

    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'nexu',
            Email = 'newexpense.user@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ExpenseUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'newexpense.user.' + DateTime.now().getTime() + '@example.com',
            Employee_Level__c = 'L6'
        );
        insert u;

        insert new Travel_Eligibility_Matrix__c(
            Name = 'L6 Matrix',
            Level__c = 'L6',
            Grade__c = 'A',
            Lodging_Tier_1__c = 5000,
            Lodging_Tier_2__c = 3000,
            Lodging_Tier_3__c = 2000,
            Fooding_Tier_1__c = 1000,
            Fooding_Tier_2__c = 800,
            Fooding_Tier_3__c = 500,
            Air_Economy_Class__c = true,
            Train_3AC__c = true,
            Own_2_Wheeler_Rate_per_KM__c = 4,
            Own_4_Wheeler_Rate_per_KM__c = 8
        );
    }

    private static User getTestUser() {
        return [SELECT Id FROM User WHERE Alias = 'nexu' LIMIT 1];
    }

    @isTest
    static void testGetEligibility_Success() {
        User u = getTestUser();
        System.runAs(u) {
            Test.startTest();
            Travel_Eligibility_Matrix__c matrix = NewExpenseFormController.getEligibility();
            Test.stopTest();
            System.assertNotEquals(null, matrix);
            System.assertEquals('L6', matrix.Level__c);
        }
    }

    @isTest
    static void testGetEligibility_NoLevel() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noLevel = new User(
            Alias = 'nolvl',
            Email = 'nolevel.user@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NoLevel',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'nolevel.user.' + DateTime.now().getTime() + '@example.com'
        );
        insert noLevel;

        System.runAs(noLevel) {
            Boolean threw = false;
            Test.startTest();
            try {
                NewExpenseFormController.getEligibility();
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('Employee Level'), e.getMessage());
            }
            Test.stopTest();
            System.assert(threw, 'Should throw when Employee Level is blank');
        }
    }

    @isTest
    static void testSaveExpenseData_WithAttachment() {
        User u = getTestUser();
        System.runAs(u) {
            Map<String, Object> line = new Map<String, Object>{
                'expenseType' => 'Fooding',
                'amount' => 500,
                'travelClass' => null,
                'vehicleType' => null,
                'distanceKm' => null,
                'fileName' => 'bill',
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('fake-bill')),
                'extension' => 'jpg'
            };
            Map<String, Object> payload = new Map<String, Object>{
                'startDate' => String.valueOf(Date.today()),
                'endDate' => String.valueOf(Date.today().addDays(1)),
                'city' => 'Mumbai',
                'cityTier' => 'Tier 1',
                'lines' => new List<Object>{ line }
            };

            Test.startTest();
            String expenseName = NewExpenseFormController.saveExpenseData(JSON.serialize(payload));
            Test.stopTest();

            System.assertNotEquals(null, expenseName);
            List<Expense__c> expenses = [
                SELECT Id, Status__c, Employee_Level__c,
                       (SELECT Id, Expense_Type__c, Amount__c, Bill_Attached__c FROM Expense_Lines__r)
                FROM Expense__c
                WHERE Employee__c = :u.Id
            ];
            System.assertEquals(1, expenses.size());
            //System.assertEquals('Draft', expenses[0].Status__c);
            System.assertEquals('L6', expenses[0].Employee_Level__c);
            System.assertEquals(1, expenses[0].Expense_Lines__r.size());
            System.assertEquals(true, expenses[0].Expense_Lines__r[0].Bill_Attached__c);
        }
    }

    @isTest
    static void testSaveExpenseData_OwnVehicle() {
        User u = getTestUser();
        System.runAs(u) {
            Map<String, Object> line = new Map<String, Object>{
                'expenseType' => 'Own Vehicle',
                'amount' => 80,
                'vehicleType' => '2-Wheeler',
                'distanceKm' => 20,
                'fileName' => null,
                'base64Data' => null,
                'extension' => null
            };
            Map<String, Object> payload = new Map<String, Object>{
                'startDate' => String.valueOf(Date.today()),
                'endDate' => String.valueOf(Date.today()),
                'city' => 'Pune',
                'cityTier' => 'Tier 1',
                'lines' => new List<Object>{ line }
            };

            Test.startTest();
            String expenseName = NewExpenseFormController.saveExpenseData(JSON.serialize(payload));
            Test.stopTest();

            System.assertNotEquals(null, expenseName);
            Expense_Line__c savedLine = [
                SELECT Distance_KM__c, Vehicle_Type__c, Expense_Type__c
                FROM Expense_Line__c
                WHERE Expense__r.Employee__c = :u.Id
                LIMIT 1
            ];
            System.assertEquals(20, savedLine.Distance_KM__c);
            System.assertEquals('Own Vehicle', savedLine.Expense_Type__c);
        }
    }
}