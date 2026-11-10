public class NewExpenseFormController {

    @AuraEnabled(cacheable=true)
    public static Travel_Eligibility_Matrix__c getEligibility() {
        try {
            User currentUser = [
                SELECT Id, Employee_Level__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (String.isBlank(currentUser.Employee_Level__c)) {
                throw buildAuraException('Employee Level is not set on your user record. Please contact admin.');
            }

            List<Travel_Eligibility_Matrix__c> matrices = [
                SELECT Id, Name, Level__c, Grade__c, Designations__c,
                       Lodging_Tier_1__c, Lodging_Tier_2__c, Lodging_Tier_3__c,
                       Fooding_Tier_1__c, Fooding_Tier_2__c, Fooding_Tier_3__c,
                       Air_Business_Class__c, Air_Economy_Class__c,
                       Train_1AC__c, Train_2AC__c, Train_3AC__c, Train_Sleeper__c,
                       Ola_Uber_Taxi__c, Car_Rental__c, Auto__c, Bus__c,
                       Own_2_Wheeler_Rate_per_KM__c, Own_4_Wheeler_Rate_per_KM__c
                FROM Travel_Eligibility_Matrix__c
                WHERE Level__c = :currentUser.Employee_Level__c
                LIMIT 1
            ];

            if (matrices.isEmpty()) {
                throw buildAuraException(
                    'No Travel Eligibility Matrix found for level ' + currentUser.Employee_Level__c + '.'
                );
            }

            return matrices[0];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    @AuraEnabled
    public static String saveExpenseData(String payload) {
        try {
            ExpensePayload data = (ExpensePayload) JSON.deserialize(payload, ExpensePayload.class);

            Id currentUserId = UserInfo.getUserId();
            User currentUser = [SELECT Id, Employee_Level__c, ManagerId, Department FROM User WHERE Id = :currentUserId LIMIT 1];

            Expense__c exp = new Expense__c();
            exp.Travel_Start_Date__c = data.startDate;
            exp.Travel_End_Date__c = data.endDate;
            exp.Status__c = 'Submitted';
            exp.Employee__c = currentUserId;
            exp.Employee_Level__c = currentUser.Employee_Level__c;
            exp.Approver__c = currentUser.ManagerId;
            exp.User_Department__c = currentUser.Department != null ? currentUser.Department : null;
            exp.Submitted_Date__c = Date.today();

            insert exp;

            List<Expense_Line__c> linesToInsert = new List<Expense_Line__c>();
            for (ExpenseLineWrapper lineData : data.lines) {
                Expense_Line__c line = new Expense_Line__c();
                line.Expense__c = exp.Id;
                line.Expense_Type__c = lineData.expenseType;
                line.Amount__c = lineData.amount;
                line.City__c = data.city;
                line.City_Tier__c = data.cityTier;
                line.Travel_Class__c = lineData.travelClass;
                line.Vehicle_Type__c = lineData.vehicleType;
                if (lineData.distanceKm != null) {
                    line.Distance_KM__c = lineData.distanceKm;
                }

                if (String.isNotBlank(lineData.base64Data)) {
                    line.Bill_Attached__c = true;
                }
                linesToInsert.add(line);
            }
            insert linesToInsert;

            List<ContentVersion> cvList = new List<ContentVersion>();
            for (Integer i = 0; i < data.lines.size(); i++) {
                ExpenseLineWrapper lineData = data.lines[i];
                if (String.isNotBlank(lineData.base64Data)) {
                    ContentVersion cv = new ContentVersion();
                    cv.Title = lineData.fileName;
                    cv.PathOnClient = lineData.fileName + '.' + lineData.extension;
                    cv.VersionData = EncodingUtil.base64Decode(lineData.base64Data);
                    // cv.FirstPublishLocationId = linesToInsert[i].Id;
                    cv.FirstPublishLocationId = exp.Id;
                    cvList.add(cv);
                }
            }
            if (!cvList.isEmpty()) {
                insert cvList;
            }

            Expense__c savedExp = [SELECT Name FROM Expense__c WHERE Id = :exp.Id LIMIT 1];
            return savedExp.Name;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw buildAuraException(e.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    public class ExpensePayload {
        public Date startDate;
        public Date endDate;
        public String city;
        public String cityTier;
        public List<ExpenseLineWrapper> lines;
    }

    public class ExpenseLineWrapper {
        public String expenseType;
        public Decimal amount;
        public String travelClass;
        public String vehicleType;
        public Decimal distanceKm;
        public String fileName;
        public String base64Data;
        public String extension;
    }
}