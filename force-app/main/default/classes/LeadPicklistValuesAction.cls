/*
 public without sharing class LeadPicklistValuesAction {

    public class Request {
        @InvocableVariable(label='Input' description='Not used, leave blank')
        public String dummyValue;
    }

    public class Response {
        @InvocableVariable(label='Lead Source Values')
        public List<String> leadSourceValues;

        @InvocableVariable(label='Department Values')
        public List<String> departmentValues;

        @InvocableVariable(label='Previous Source Values')
        public List<String> previousSourceValues;
    }

    @InvocableMethod(label='Get Lead Picklist Values'
                     description='Returns active picklist values for LeadSource (profile filtered), Department, and PreviousSource')
    public static List<Response> getLeadPicklistValues(List<Request> requests) {
        Response res = new Response();
        
        List<String> allLeadSources = getPicklistValues('Lead', 'LeadSource');
        res.leadSourceValues     = filterForRunningUser(allLeadSources);
        res.departmentValues     = getPicklistValues('Lead', 'Department_Name__c');
        res.previousSourceValues = getPicklistValues('Lead', 'Previous_Source__c');
        
        return new List<Response>{ res };
            }
    
    private static List<String> filterForRunningUser(List<String> allValues) {
        
        String profileName = null;
        try {
            Id currentUserId = UserInfo.getUserId();
            List<User> users = Database.query(
                'SELECT Profile.Name FROM User WHERE Id = :currentUserId LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            if (!users.isEmpty()) {
                profileName = users[0].Profile?.Name;
            }
        } catch (Exception e) {
            profileName = null;
        }
        
        if (String.isBlank(profileName)) {
            return allValues;
        }
        
        String allowedRaw = null;
        for (Profile_wise_Lead_Source_Agentforce__mdt cfg :
             [SELECT MasterLabel, Lead_Source__c
              FROM Profile_wise_Lead_Source_Agentforce__mdt]) {
                  
                  if (String.isBlank(cfg.MasterLabel)) continue;
                  
                  for (String p : cfg.MasterLabel.split(',')) {
                      if (p.trim().equalsIgnoreCase(profileName)) {
                          allowedRaw = cfg.Lead_Source__c;
                          break;
                      }
                  }
                  if (allowedRaw != null) break;
              }
        
        if (String.isBlank(allowedRaw)) return allValues;
        
        Set<String> allowed = new Set<String>();
        for (String v : allowedRaw.replace('\r','').split('[\n,]+')) {
            String t = v.trim();
            if (String.isNotBlank(t)) allowed.add(t.toLowerCase());
        }
        
        List<String> result = new List<String>();
        for (String v : allValues) {
            if (allowed.contains(v.toLowerCase())) result.add(v);
        }
        return result;
    }

    private static List<String> getPicklistValues(String objectApiName, String fieldApiName) {
        List<String> values = new List<String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType != null) {
            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
            if (fieldMap.containsKey(fieldApiName)) {
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldApiName).getDescribe();
                for (Schema.PicklistEntry entry : fieldDesc.getPicklistValues()) {
                    if (entry.isActive()) values.add(entry.getValue());
                }
            }
        }
        return values;
    }
}
*/
public without sharing class LeadPicklistValuesAction {

    public class Request {
        @InvocableVariable(label='Input' description='Not used, leave blank')
        public String dummyValue;
    }

    public class Response {
        @InvocableVariable(label='Lead Source Values')
        public List<String> leadSourceValues;

        @InvocableVariable(label='Department Values')
        public List<String> departmentValues;

        @InvocableVariable(label='Previous Source Values')
        public List<String> previousSourceValues;

        @InvocableVariable(label='Department Count'
            description='Number of Department values returned for the running user after filtering.')
        public Integer departmentCount;
    }

    @InvocableMethod(label='Get Lead Picklist Values'
                     description='Returns active picklist values for LeadSource (profile filtered), Department (user filtered), and PreviousSource')
    public static List<Response> getLeadPicklistValues(List<Request> requests) {
        Response res = new Response();

        // One query, used by both filters.
        User runningUser = getRunningUserContext();
        String profileName     = (runningUser != null) ? runningUser.Profile?.Name : null;
        String userDepartments = (runningUser != null) ? runningUser.Departments__c : null;

        List<String> allLeadSources = getPicklistValues('Lead', 'LeadSource');
        res.leadSourceValues = filterLeadSourceForProfile(allLeadSources, profileName);

        List<String> allDepartments = getPicklistValues('Lead', 'Department_Name__c');
        res.departmentValues = filterDepartmentsForUser(allDepartments, userDepartments);
        res.departmentCount  = res.departmentValues.size();

        res.previousSourceValues = getPicklistValues('Lead', 'Previous_Source__c');

        return new List<Response>{ res };
    }

    // ---------- shared context ----------

    private static User getRunningUserContext() {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<User> users = Database.query(
                'SELECT Profile.Name, Departments__c FROM User WHERE Id = :currentUserId LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );
            return users.isEmpty() ? null : users[0];
        } catch (Exception e) {
            return null;
        }
    }

    // ---------- Lead Source filter (profile based) ----------

    private static List<String> filterLeadSourceForProfile(List<String> allValues, String profileName) {

        if (String.isBlank(profileName)) return allValues;

        String allowedRaw = null;
        for (Profile_wise_Lead_Source_Agentforce__mdt cfg :
                [SELECT MasterLabel, Lead_Source__c
                 FROM Profile_wise_Lead_Source_Agentforce__mdt]) {

            if (String.isBlank(cfg.MasterLabel)) continue;

            for (String p : cfg.MasterLabel.split(',')) {
                if (p.trim().equalsIgnoreCase(profileName)) {
                    allowedRaw = cfg.Lead_Source__c;
                    break;
                }
            }
            if (allowedRaw != null) break;
        }

        if (String.isBlank(allowedRaw)) return allValues;

        Set<String> allowed = new Set<String>();
        for (String v : allowedRaw.replace('\r', '').split('[\n,]+')) {
            String t = v.trim();
            if (String.isNotBlank(t)) allowed.add(t.toLowerCase());
        }

        List<String> result = new List<String>();
        for (String v : allValues) {
            if (allowed.contains(v.toLowerCase())) result.add(v);
        }
        return result;
    }

    // ---------- Department filter (user's Departments__c based) ----------

    private static List<String> filterDepartmentsForUser(List<String> allDeptValues, String userDepartmentsRaw) {

        // No department set on the user -> show everything.
        if (String.isBlank(userDepartmentsRaw)) return allDeptValues;

        Set<String> userDeptTokens = new Set<String>();
        for (String tok : userDepartmentsRaw.split(';')) {
            String t = tok.trim();
            if (String.isNotBlank(t)) userDeptTokens.add(t.toLowerCase());
        }
        if (userDeptTokens.isEmpty()) return allDeptValues;

        Set<String> allowedLeadDepts = new Set<String>();
        for (User_Lead_department_map_Agentforce__mdt cfg :
                [SELECT User_Department_API_Name__c, Lead_Department_API_Name__c
                 FROM User_Lead_department_map_Agentforce__mdt]) {

            if (String.isBlank(cfg.User_Department_API_Name__c)
                    || String.isBlank(cfg.Lead_Department_API_Name__c)) continue;

            if (userDeptTokens.contains(cfg.User_Department_API_Name__c.trim().toLowerCase())) {
                allowedLeadDepts.add(cfg.Lead_Department_API_Name__c.trim().toLowerCase());
            }
        }

        // User HAS departments, but none matched any metadata row.
        // Falling back to "show all" here rather than an empty list — flip this
        // to `return new List<String>();` if you'd rather force a data fix.
        if (allowedLeadDepts.isEmpty()) return allDeptValues;

        List<String> result = new List<String>();
        for (String v : allDeptValues) {
            if (allowedLeadDepts.contains(v.trim().toLowerCase())) result.add(v);
        }
        return result;
    }

    private static List<String> getPicklistValues(String objectApiName, String fieldApiName) {
        List<String> values = new List<String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType != null) {
            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
            if (fieldMap.containsKey(fieldApiName)) {
                Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldApiName).getDescribe();
                for (Schema.PicklistEntry entry : fieldDesc.getPicklistValues()) {
                    if (entry.isActive()) values.add(entry.getValue());
                }
            }
        }
        return values;
    }
}