/**
 * @description Test class for ExpenseTriggerHandler.
 * Invokes handler methods directly so org validation/flows cannot
 * hide trigger field updates during DML.
 */
@IsTest
private class ExpenseTriggerHandlerTest {
  private static Expense__c insertDraftExpense() {
    Expense__c expense = new Expense__c();
    insert as system expense;
    return expense;
  }

  @IsTest
  static void testBeforeInsertDefaults() {
    Expense__c expense = new Expense__c();
    ExpenseTriggerHandler.beforeInsert(new List<Expense__c>{ expense });

    System.assertEquals('Draft', expense.Status__c);
    System.assertEquals(UserInfo.getUserId(), expense.Employee__c);
  }

  @IsTest
  static void testAfterUpdateCollectsSubmittedExpenses() {
    Expense__c inserted = insertDraftExpense();
    Expense__c oldExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Draft',
      Employee__c = UserInfo.getUserId()
    );
    Expense__c newExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Submitted',
      Employee__c = UserInfo.getUserId()
    );

    Test.startTest();
    ExpenseTriggerHandler.beforeUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );
    ExpenseTriggerHandler.afterUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );
    Test.stopTest();

    System.assertEquals('Submitted', newExpense.Status__c);
    System.assertEquals(Date.today(), newExpense.Submitted_Date__c);
  }

  @IsTest
  static void testBeforeUpdateApprovedPath() {
    Expense__c inserted = insertDraftExpense();
    Expense__c oldExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Submitted',
      Employee__c = UserInfo.getUserId()
    );
    Expense__c newExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Approved',
      Employee__c = UserInfo.getUserId()
    );

    Test.startTest();
    ExpenseTriggerHandler.beforeUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );
    ExpenseTriggerHandler.afterUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );
    Test.stopTest();

    System.assertEquals('Approved', newExpense.Status__c);
    System.assertEquals(Date.today(), newExpense.Approval_Date__c);
    System.assertEquals(UserInfo.getUserId(), newExpense.Approver__c);
  }

  @IsTest
  static void testBeforeDeleteBlocksNonDraft() {
    Expense__c inserted = insertDraftExpense();
    Expense__c submitted = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Submitted',
      Employee__c = UserInfo.getUserId()
    );

    Test.startTest();
    ExpenseTriggerHandler.beforeDelete(new List<Expense__c>{ submitted });
    Test.stopTest();

    System.assertEquals(true, submitted.hasErrors());
  }

  @IsTest
  static void testBeforeInsertKeepsProvidedValues() {
    Expense__c expense = new Expense__c(
      Status__c = 'Submitted',
      Employee__c = UserInfo.getUserId()
    );
    ExpenseTriggerHandler.beforeInsert(new List<Expense__c>{ expense });
    System.assertEquals('Submitted', expense.Status__c);
    System.assertEquals(UserInfo.getUserId(), expense.Employee__c);
  }

  @IsTest
  static void testBeforeUpdateBlocksApprovedModification() {
    Expense__c inserted = insertDraftExpense();
    Expense__c oldExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Approved'
    );
    Expense__c newExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Draft'
    );

    ExpenseTriggerHandler.beforeUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );

    System.assertEquals(true, newExpense.hasErrors());
  }

  @IsTest
  static void testBeforeUpdateAllowsReimbursedFromApproved() {
    Expense__c inserted = insertDraftExpense();
    Expense__c oldExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Approved'
    );
    Expense__c newExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Reimbursed'
    );

    ExpenseTriggerHandler.beforeUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );

    System.assertEquals(false, newExpense.hasErrors());
  }

  @IsTest
  static void testAfterInsertAndRejectedAfterUpdate() {
    Expense__c inserted = insertDraftExpense();
    ExpenseTriggerHandler.afterInsert(new List<Expense__c>{ inserted });

    Expense__c oldExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Submitted'
    );
    Expense__c newExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Rejected'
    );

    ExpenseTriggerHandler.afterUpdate(
      new List<Expense__c>{ newExpense },
      new Map<Id, Expense__c>{ inserted.Id => oldExpense }
    );

    System.assertEquals('Rejected', newExpense.Status__c);
  }

  @IsTest
  static void testBeforeDeleteAllowsDraft() {
    Expense__c inserted = insertDraftExpense();
    Expense__c draftExpense = new Expense__c(
      Id = inserted.Id,
      Status__c = 'Draft'
    );

    ExpenseTriggerHandler.beforeDelete(new List<Expense__c>{ draftExpense });
    System.assertEquals(false, draftExpense.hasErrors());
  }
}