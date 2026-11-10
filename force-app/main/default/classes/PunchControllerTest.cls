@isTest
private class PunchControllerTest {

    // ─── Setup ────────────────────────────────────────────────────────────────
    @TestSetup
    static void makeData() {
        // Create a test Employee__c record for legacy method testing
        Employee__c emp = new Employee__c();
        emp.Current_Status__c = 'OUT';
        insert emp;
    }

    // ─── User-based tests (using User_Punch_State__c) ─────────────────────────

    @isTest
    static void testGetCurrentStateForUser_NoStateRecord() {
        // No User_Punch_State__c exists yet — should return default OUT
        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.getCurrentStateForUser();
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals(UserInfo.getUserId(), dto.userId, 'userId should match running user');
        System.assertNotEquals(null, dto.employeeName, 'Employee name should not be null');
        System.assertEquals('OUT', dto.currentStatus, 'Default status should be OUT when no state record exists');
        System.assertEquals('Rejected', dto.wfhRequestStatusTomorrow, 'WFH status should be Rejected when no approved request exists');
    }

    @isTest
    static void testPunchNowAsUser_PunchIn() {
        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.punchNowAsUser(
            12.9716,    // latitude
            77.5946,    // longitude
            85.0,       // battery
            null,       // selfie
            null,       // no odometer
            'punch.jpg',// filename
            '',         // punchType ignored — Day In only
            null,       // wfhActivity
            null,       // transportType
            null,       // vehicleType
            null,       // odometerReading
            null,       // extractedOdometer
            'iOS',      // deviceOS
            'iPhone'    // deviceModel
        );
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals('IN', dto.currentStatus, 'Status should be IN after Day In');
        System.assertEquals(null, dto.lastPunchType, 'Day In alone should not start a mode');
    }

    @isTest
    static void testPunchNowAsUser_PunchInThenOut() {
        // Day In (no mode)
        PunchController.punchNowAsUser(12.9716, 77.5946, 85.0, null, null, 'p.jpg', '', null, null, null, null, null, 'iOS', 'iPhone');

        Test.startTest();
        // Day Out — allowed when no active mode
        PunchController.PunchStateDTO dto = PunchController.punchNowAsUser(
            12.9716, 77.5946, 80.0, null, null, 'p.jpg', '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        Test.stopTest();

        System.assertEquals('OUT', dto.currentStatus, 'Status should be OUT after Day Out');
    }

    @isTest
    static void testPunchNowAsUser_WithImage() {
        String fakeBase64 = 'data:image/jpeg;base64,' + EncodingUtil.base64Encode(Blob.valueOf('FAKE_IMAGE_DATA'));

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.punchNowAsUser(
            12.9716, 77.5946, 90.0, fakeBase64, null, 'selfie_test.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        
        List<Punch_Record__c> punches = [SELECT Id FROM Punch_Record__c WHERE User__c = :UserInfo.getUserId() ORDER BY CreatedDate DESC LIMIT 1];
        System.assertEquals(1, punches.size(), 'A punch record should exist');
        
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :punches[0].Id];
        System.assert(links.size() > 0, 'At least one content document should be linked to the punch record');
    }

    @isTest
    static void testStartWFH_Approved() {
        Punch_Record__c req = new Punch_Record__c();
        req.User__c = UserInfo.getUserId();
        req.Is_WFH_Request__c = true;
        req.WFH_Request_Date__c = Date.today();
        req.WFH_Approval_Status__c = 'Approved';
        insert req;

        PunchController.punchNowAsUser(
            12.9716, 77.5946, 85.0, null, null, 'wfh.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.updatePunchTypeAndOdometer(
            'WFH', null, null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals('IN', dto.currentStatus);
        System.assertEquals('WFH', dto.lastPunchType);
    }

    @isTest
    static void testEndWFH_WithDayActivityLog() {
        Punch_Record__c req = new Punch_Record__c();
        req.User__c = UserInfo.getUserId();
        req.Is_WFH_Request__c = true;
        req.WFH_Request_Date__c = Date.today();
        req.WFH_Approval_Status__c = 'Approved';
        insert req;

        PunchController.punchNowAsUser(
            12.9716, 77.5946, 85.0, null, null, 'wfh.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        PunchController.updatePunchTypeAndOdometer(
            'WFH', null, null, null, null, null, null
        );

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.updatePunchTypeAndOdometer(
            '', null, null, null, null, null, null,
            5, 3, 2, 1, 'Follow up with accounts'
        );
        Test.stopTest();

        System.assertEquals(null, dto.lastPunchType, 'WFH mode should be cleared');

        Punch_Record__c outRec = [
            SELECT No_of_Phone_Calls__c, No_of_Emails__c, No_of_Offers_Sent__c,
                   No_of_Meetings__c, Open_Notes__c, Punch_Type__c, Action__c
            FROM Punch_Record__c
            WHERE User__c = :UserInfo.getUserId()
              AND Action__c = 'OUT'
              AND Punch_Type__c = 'WFH'
            ORDER BY Punch_Time__c DESC
            LIMIT 1
        ];
        System.assertEquals(5, outRec.No_of_Phone_Calls__c);
        System.assertEquals(3, outRec.No_of_Emails__c);
        System.assertEquals(2, outRec.No_of_Offers_Sent__c);
        System.assertEquals(1, outRec.No_of_Meetings__c);
        System.assertEquals('Follow up with accounts', outRec.Open_Notes__c);
    }

    @isTest
    static void testStartWFH_NotApproved() {
        PunchController.punchNowAsUser(
            12.9716, 77.5946, 85.0, null, null, 'wfh.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );

        Test.startTest();
        Boolean threw = false;
        try {
            PunchController.updatePunchTypeAndOdometer(
                'WFH', null, null, null, null, null, null
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Should have thrown an exception for unapproved WFH mode start');
    }

    @isTest
    static void testSubmitWFHRequest() {
        Date tomorrow = Date.today().addDays(1);
        String startTime = '09:00:00.000';
        String endTime = '18:00:00.000';

        Test.startTest();
        PunchController.submitWFHRequest(tomorrow, startTime, endTime, 'WFH', 'Test WFH Request Note');
        Test.stopTest();

        List<Punch_Record__c> reqs = [SELECT Id, WFH_Request_Date__c, WFH_Approval_Status__c FROM Punch_Record__c WHERE Is_WFH_Request__c = true];
        System.assertEquals(1, reqs.size(), 'One WFH request should be created');
        System.assertEquals(tomorrow, reqs[0].WFH_Request_Date__c);
        System.assertEquals('Pending', reqs[0].WFH_Approval_Status__c);
    }

    @isTest
    static void testStartMarketVisitMode() {
        PunchController.punchNowAsUser(
            12.9716, 77.5946, 80.0, null, null, 'market.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.updatePunchTypeAndOdometer(
            'Market Visit',
            'Private Vehicle',
            'Two Wheeler',
            12345,
            12340,
            null,
            null
        );
        Test.stopTest();

        System.assertEquals('IN', dto.currentStatus);
        System.assertEquals('Market Visit', dto.lastPunchType);
    }

    @isTest
    static void testDayOutBlockedWhileModeActive() {
        PunchController.punchNowAsUser(
            12.9716, 77.5946, 85.0, null, null, 'p.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        PunchController.updatePunchTypeAndOdometer(
            'Market Visit', 'Public Transport', null, null, null, null, null
        );

        Test.startTest();
        Boolean threw = false;
        try {
            PunchController.punchNowAsUser(
                12.9716, 77.5946, 80.0, null, null, 'p.jpg',
                '', null, null, null, null, null, 'iOS', 'iPhone'
            );
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();
        System.assert(threw, 'Day Out should be blocked while mode is active');
    }

    @isTest
    static void testModeEndThenDayOut() {
        PunchController.punchNowAsUser(
            12.9716, 77.5946, 85.0, null, null, 'p.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        PunchController.updatePunchTypeAndOdometer(
            'Market Visit', 'Public Transport', null, null, null, null, null
        );
        PunchController.updatePunchTypeAndOdometer(
            '', null, null, null, null, null, null
        );

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.punchNowAsUser(
            12.9716, 77.5946, 80.0, null, null, 'p.jpg',
            '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        Test.stopTest();

        System.assertEquals('OUT', dto.currentStatus, 'Day Out should succeed after mode end');
        System.assertEquals(null, dto.lastPunchType);
    }

    // ─── Legacy Employee__c tests ─────────────────────────────────────────────

    @isTest
    static void testGetCurrentState_Employee() {
        Employee__c emp = [SELECT Id FROM Employee__c LIMIT 1];

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.getCurrentState(emp.Id);
        Test.stopTest();

        System.assertNotEquals(null, dto, 'DTO should not be null');
        System.assertEquals(emp.Id, dto.employeeId, 'employeeId should match');
        System.assertEquals('OUT', dto.currentStatus, 'Default status should be OUT');
    }

    @isTest
    static void testPunchNow_Employee_PunchIn() {
        Employee__c emp = [SELECT Id FROM Employee__c LIMIT 1];

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.punchNow(
            emp.Id, 12.9716, 77.5946, 75.0, null, null
        );
        Test.stopTest();

        System.assertEquals('IN', dto.currentStatus, 'Status should be IN');
    }

    @isTest
    static void testGetWFHRequestsForUser() {
        Id runningUserId = UserInfo.getUserId();
        
        // Create WFH request
        Punch_Record__c wfh = new Punch_Record__c();
        wfh.User__c = runningUserId;
        wfh.Is_WFH_Request__c = true;
        wfh.WFH_Request_Date__c = Date.today();
        wfh.WFH_Request_Start_Time__c = Time.newInstance(9, 0, 0, 0);
        wfh.WFH_Request_End_Time__c = Time.newInstance(18, 0, 0, 0);
        wfh.WFH_Approval_Status__c = 'Pending';
        insert wfh;

        // Create WFO request
        Punch_Record__c wfo = new Punch_Record__c();
        wfo.User__c = runningUserId;
        wfo.Is_WFO_Request__c = true;
        wfo.WFH_Request_Date__c = Date.today().addDays(1);
        wfo.WFH_Request_Start_Time__c = Time.newInstance(10, 0, 0, 0);
        wfo.WFH_Request_End_Time__c = Time.newInstance(19, 0, 0, 0);
        wfo.WFH_Approval_Status__c = 'Approved';
        wfo.Approver_Remarks__c = 'Approved by HOD for office day';
        wfo.WFH_Approver__c = runningUserId;
        insert wfo;

        Test.startTest();
        List<PunchController.WFHRequestDetail> requests = PunchController.getWFHRequestsForUser(runningUserId);
        Test.stopTest();

        System.assertEquals(2, requests.size(), 'Should have returned 2 requests');
        // Sorted by WFH_Request_Date__c DESC, so tomorrow's request first (WFO)
        System.assertEquals('WFO', requests[0].type);
        System.assertEquals('Approved', requests[0].status);
        System.assertEquals('Approved by HOD for office day', requests[0].remarks);
        System.assertEquals(runningUserId, requests[0].approverId);
        System.assertEquals(UserInfo.getName(), requests[0].approverName);
        System.assertEquals('WFH', requests[1].type);
        System.assertEquals('Pending', requests[1].status);
        System.assertEquals(null, requests[1].remarks);

        PunchController.PunchStateDTO state = PunchController.getCurrentStateForUser();
        System.assertEquals(2, state.wfhRequests.size(), 'Sales user state should include WFH/WFO request details');
        System.assertEquals('Approved by HOD for office day', state.wfhRequests[0].remarks);
        System.assertEquals(UserInfo.getName(), state.wfhRequests[0].approverName);
    }

    @isTest
    static void testUnclosedWfhWfoPunchOutBlocked() {
        Id runningUserId = UserInfo.getUserId();
        
        Punch_Record__c wfh = new Punch_Record__c(
            User__c = runningUserId,
            Is_WFH_Request__c = true,
            WFH_Request_Date__c = Date.today(),
            WFH_Approval_Status__c = 'Approved'
        );
        insert wfh;

        // Day In with no mode — Day Out should succeed
        PunchController.punchNowAsUser(12.9716, 77.5946, 85.0, null, null, 'p.jpg', '', null, null, null, null, null, 'iOS', 'iPhone');

        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.punchNowAsUser(
            12.9716, 77.5946, 80.0, null, null, 'p.jpg', '', null, null, null, null, null, 'iOS', 'iPhone'
        );
        Test.stopTest();

        System.assertEquals('OUT', dto.currentStatus, 'Day Out should succeed when no mode is active');
    }

    @isTest
    static void testUpdatePunchTypeAndOdometer() {
        Id runningUserId = UserInfo.getUserId();
        
        // 1. Day In
        PunchController.punchNowAsUser(12.9716, 77.5946, 85.0, null, null, 'p.jpg', '', null, null, null, null, null, 'iOS', 'iPhone');
        
        // 2. Start Market Visit mode with odometer
        Test.startTest();
        PunchController.PunchStateDTO dto = PunchController.updatePunchTypeAndOdometer(
            'Market Visit',
            'Private Vehicle',
            'Two Wheeler',
            1000.0,
            1000.0,
            'dGVzdF9kYXRh', // base64 string "test_data"
            'odo.jpg'
        );
        Test.stopTest();
        
        System.assertEquals('Market Visit', dto.lastPunchType, 'Active mode should be updated to Market Visit');
        System.assertEquals('Private Vehicle', dto.lastTransportType, 'Transport should be Private');
        System.assertEquals('Two Wheeler', dto.lastVehicleType, 'Vehicle should be Two Wheeler');
        
        Punch_Record__c pr = [
            SELECT Id FROM Punch_Record__c
            WHERE User__c = :runningUserId AND Action__c = 'IN' AND Punch_Type__c = 'Market Visit'
            ORDER BY Punch_Time__c DESC
            LIMIT 1
        ];
        List<ContentDocumentLink> cdls = [SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId = :pr.Id];
        System.assert(!cdls.isEmpty(), 'Odometer image should be attached to the punch record');
    }
}