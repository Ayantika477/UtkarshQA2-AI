public class PunchOutHandler {

    public static void calculateDistance(List<User_Punch_State__c> outRecords) {
        
        // Collect the rate from metadata
        Map<String, Decimal> rateMap = new Map<String, Decimal>();
        
        for (Employee_Level_Rate_KM__mdt mdt : [
                SELECT Employee_Level__c, Vehical_Type__c, Rate_Per_KM__c
                FROM Employee_Level_Rate_KM__mdt]) {
    
            // Composite key: "L2|2-Wheeler"
            String key = mdt.Employee_Level__c + '|' + mdt.Vehical_Type__c;
            rateMap.put(key, mdt.Rate_Per_KM__c);
        }
        
        // Collect User IDs to query their Employee Level
        Set<Id> userIds = new Set<Id>();
        for (User_Punch_State__c state : outRecords) {
            if (state.OwnerId != null) userIds.add(state.OwnerId);
        }

        // Query User with Employee Level
        Map<Id, User> userMap = new Map<Id, User>(
            [SELECT Id, Employee_Level__c FROM User WHERE Id IN :userIds]
        );
        

        Set<Id> punchRecordIds = new Set<Id>();
        for (User_Punch_State__c state : outRecords) {
            if (state.Punch_In_Record__c  != null) punchRecordIds.add(state.Punch_In_Record__c);
            if (state.Punch_Out_Record__c != null) punchRecordIds.add(state.Punch_Out_Record__c);
        }
        

        // Query both IN and OUT punch records
        Map<Id, Punch_Record__c> punchMap = new Map<Id, Punch_Record__c>(
            [SELECT Id, Odometer_Reading__c, Status__c, Vehicle_Type__c, Extracted_Odometer_Reading__c, createdDate
             FROM Punch_Record__c
             WHERE Id IN :punchRecordIds]);


             List<ShiftExpenseData> shiftDataList = new List<ShiftExpenseData>();

        for (User_Punch_State__c state : outRecords) {

            Punch_Record__c inRecord  = punchMap.get(state.Punch_In_Record__c);
            Punch_Record__c outRecord = punchMap.get(state.Punch_Out_Record__c);

            if (inRecord == null || outRecord == null) continue;
            if (inRecord.Extracted_Odometer_Reading__c == null || outRecord.Extracted_Odometer_Reading__c == null) continue;

            Decimal inRecordValue = inRecord.Odometer_Reading__c != null ? inRecord.Odometer_Reading__c : inRecord.Extracted_Odometer_Reading__c;
            Decimal outRecordValue = outRecord.Odometer_Reading__c != null ? outRecord.Odometer_Reading__c : outRecord.Extracted_Odometer_Reading__c;
            
            Decimal distanceTravelled = outRecordValue - inRecordValue;
            String  vehicleType       = outRecord.Vehicle_Type__c;
            Date startDate = inRecord.CreatedDate.date();
			Date endDate = outRecord.CreatedDate.date();
        
            // Get user designation
            User usr = userMap.get(state.OwnerId);
            String  employeeLevel = (usr != null && usr.Employee_Level__c != null) ? usr.Employee_Level__c.toUpperCase().trim() : '';
			
            if(String.isEmpty(employeeLevel)) continue;

            // Get rate based on level + vehicle type
            String rateKey   = employeeLevel + '|' + vehicleType;
            Decimal ratePerKm     = rateMap.containsKey(rateKey) ? rateMap.get(rateKey) : 0;
            Decimal expenseAmount = distanceTravelled * ratePerKm;

            
             System.debug('State Id: '   + state.Id
                + ' | Distance: '       + distanceTravelled
                + ' | Vehicle Type: '   + vehicleType);
        
            ShiftExpenseData data = new ShiftExpenseData();
            data.userId        = state.User__c;
            data.employeeLevel = employeeLevel;
            data.startDate     = startDate;
            data.endDate       = endDate;
            data.distance      = distanceTravelled;
            data.ratePerKm     = ratePerKm;
            data.amount        = distanceTravelled * ratePerKm;
            data.vehicleType   = vehicleType;
            shiftDataList.add(data);

        }
        if (!shiftDataList.isEmpty()) {
            createExpenseRecords(shiftDataList);
        }
    }  

        
     //------------------ Creates Expense__c and Expense_Line__c on checkOut
     
    private static void createExpenseRecords(List<ShiftExpenseData> shiftDataList) {

        // Insert headers first so the lines can reference their Ids
        List<Expense__c> expenses = new List<Expense__c>();
        for (ShiftExpenseData data : shiftDataList) {
            expenses.add(new Expense__c(
                Employee__c         = data.userId,
                Employee_Level__c   = data.employeeLevel,
                Status__c           = 'Draft',
                Purpose__c          = 'Market Visit - Own vehicle travel reimbursement',
                Travel_Start_Date__c = data.startDate,
                Travel_End_Date__c   = data.endDate,
                Submitted_Date__c   = System.now().date()
            ));
        }
        insert expenses;

        // Lines: shiftDataList and expenses share the same index order
        List<Expense_Line__c> lines = new List<Expense_Line__c>();
        for (Integer i = 0; i < shiftDataList.size(); i++) {
            ShiftExpenseData data = shiftDataList[i];
            lines.add(new Expense_Line__c(
                Expense__c      = expenses[i].Id,
                Expense_Type__c = 'Own Vehicle',
                Vehicle_Type__c = mapVehicleTypePicklist(data.vehicleType),
                Distance_KM__c  = data.distance,
                Amount__c       = data.amount,
                Date__c         = data.endDate,
                Description__c  = 'Distance ' + data.distance + ' KM x Rs.'
                                + data.ratePerKm + '/KM (' + data.vehicleType + ')',
                Bill_Attached__c = false
            ));
        }
        insert lines;
    }

     // ─── Match the vehicle value ───────────────────────────────────
    private static String mapVehicleTypePicklist(String vehicleType) {
        if (String.isBlank(vehicleType)) return null;
        String v = vehicleType.toLowerCase().trim();
        if (v.contains('four') || v.contains('4')) return '4-Wheeler';
        if (v.contains('two')  || v.contains('2')) return '2-Wheeler';
        return null;
    }

           
    private class ShiftExpenseData {
        Id     userId;
        String employeeLevel;
        Date   startDate;
        Date   endDate;
        Decimal distance;
        Decimal ratePerKm;
        Decimal amount;
        String vehicleType;
    }

}