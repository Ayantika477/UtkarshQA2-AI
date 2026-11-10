/**
 * @description Gives Case creator Edit share when owner differs from creator.
 * @author Anshita Chanda
 */
public class CaseCreatorShareHandler {
  private static final String CASE_RECORD_TYPE_DEV_NAME = 'Case';

  public static void handleAfterInsert(List<Case> newCases) {
    if (newCases == null || newCases.isEmpty()) {
      return;
    }
    createCreatorShares(filterCaseRecordType(newCases), null);
  }

  public static void handleAfterUpdate(
    List<Case> newCases,
    Map<Id, Case> oldCasesById
  ) {
    if (newCases == null || newCases.isEmpty()) {
      return;
    }
    createCreatorShares(filterCaseRecordType(newCases), oldCasesById);
  }

  private static List<Case> filterCaseRecordType(List<Case> cases) {
    Id caseRecordTypeId = getCaseRecordTypeId();
    if (caseRecordTypeId == null) {
      return new List<Case>();
    }

    List<Case> filtered = new List<Case>();
    for (Case caseRecord : cases) {
      if (caseRecord.RecordTypeId == caseRecordTypeId) {
        filtered.add(caseRecord);
      }
    }
    return filtered;
  }

  private static Id getCaseRecordTypeId() {
    RecordTypeInfo info = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
      .get(CASE_RECORD_TYPE_DEV_NAME);
    return info == null ? null : info.getRecordTypeId();
  }

  private static void createCreatorShares(
    List<Case> newCases,
    Map<Id, Case> oldCasesById
  ) {
    List<CaseShare> sharesToInsert = new List<CaseShare>();

    for (Case caseRecord : newCases) {
      Boolean ownerChanged =
        oldCasesById == null ||
        (oldCasesById.containsKey(caseRecord.Id) &&
        caseRecord.OwnerId != oldCasesById.get(caseRecord.Id).OwnerId);

      if (!ownerChanged) {
        continue;
      }
      if (caseRecord.CreatedById == caseRecord.OwnerId) {
        continue;
      }

      sharesToInsert.add(
        new CaseShare(
          CaseId = caseRecord.Id,
          UserOrGroupId = caseRecord.CreatedById,
          CaseAccessLevel = 'Edit',
          RowCause = 'Manual'
        )
      );
    }

    if (!sharesToInsert.isEmpty()) {
      Database.insert(sharesToInsert, false);
    }
  }
}