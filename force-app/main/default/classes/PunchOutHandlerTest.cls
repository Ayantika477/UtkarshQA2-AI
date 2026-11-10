@isTest
private class PunchOutHandlerTest {

    @isTest
    static void testCalculateDistanceCreatesExpense() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'pohu',
            Email = 'punchout.handler@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PunchOut',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            UserName = 'punchout.handler.' + DateTime.now().getTime() + '@example.com',
            Employee_Level__c = 'L6'
        );
        insert u;

        System.runAs(u) {
            Punch_Record__c punchIn = new Punch_Record__c(
                User__c = u.Id,
                Action__c = 'IN',
                Punch_Time__c = System.now().addHours(-8),
                Punch_Type__c = 'Market Visit',
                Vehicle_Type__c = 'Two Wheeler',
                Odometer_Reading__c = 100,
                Extracted_Odometer_Reading__c = 100
            );
            insert punchIn;

            Punch_Record__c punchOut = new Punch_Record__c(
                User__c = u.Id,
                Action__c = 'OUT',
                Punch_Time__c = System.now(),
                Punch_Type__c = 'Market Visit',
                Vehicle_Type__c = 'Two Wheeler',
                Odometer_Reading__c = 130,
                Extracted_Odometer_Reading__c = 130
            );
            insert punchOut;

            User_Punch_State__c state = new User_Punch_State__c(
                User__c = u.Id,
                Current_Status__c = 'OUT',
                Punch_In_Record__c = punchIn.Id,
                Punch_Out_Record__c = punchOut.Id,
                Last_Punch_Time__c = System.now()
            );
            insert state;

            // OwnerId drives employee-level lookup in PunchOutHandler
            state = [SELECT Id, OwnerId, User__c, Punch_In_Record__c, Punch_Out_Record__c FROM User_Punch_State__c WHERE Id = :state.Id];

            Test.startTest();
            PunchOutHandler.calculateDistance(new List<User_Punch_State__c>{ state });
            Test.stopTest();

            List<Expense__c> expenses = [
                SELECT Id, Purpose__c, Employee__c,
                       (SELECT Expense_Type__c, Distance_KM__c, Vehicle_Type__c FROM Expense_Lines__r)
                FROM Expense__c
                WHERE Employee__c = :u.Id
            ];
            System.assertEquals(1, expenses.size(), 'Should create one expense from punch-out distance');
            System.assertEquals(1, expenses[0].Expense_Lines__r.size());
            System.assertEquals(30, expenses[0].Expense_Lines__r[0].Distance_KM__c);
            System.assertEquals('Own Vehicle', expenses[0].Expense_Lines__r[0].Expense_Type__c);
            System.assertEquals('2-Wheeler', expenses[0].Expense_Lines__r[0].Vehicle_Type__c);
        }
    }

    @isTest
    static void testCalculateDistanceSkipsIncompleteData() {
        User_Punch_State__c incomplete = new User_Punch_State__c(
            User__c = UserInfo.getUserId(),
            Current_Status__c = 'OUT'
        );
        insert incomplete;

        Test.startTest();
        PunchOutHandler.calculateDistance(new List<User_Punch_State__c>{ incomplete });
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Expense__c WHERE Purpose__c = 'Market Visit - Own vehicle travel reimbursement']
        );
    }
}