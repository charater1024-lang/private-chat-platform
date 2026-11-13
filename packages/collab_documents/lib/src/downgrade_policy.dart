/// Rights and paid-work actions are deliberately separated so losing a plan
/// cannot trap or erase existing encrypted data.
enum DocumentProductCapability {
  readExistingDocument,
  encryptedExport,
  deleteExistingDocument,
  inspectSecurityHistory,
  recoverLocalUnpublishedEdits,
  createDocument,
  publishNewEdit,
  inviteCollaborator,
  runWorkflowAutomation,
}

final class DocumentEntitlementPolicy {
  const DocumentEntitlementPolicy();

  bool isAllowed({
    required bool paidWorkEntitlementActive,
    required DocumentProductCapability capability,
  }) => switch (capability) {
    DocumentProductCapability.readExistingDocument ||
    DocumentProductCapability.encryptedExport ||
    DocumentProductCapability.deleteExistingDocument ||
    DocumentProductCapability.inspectSecurityHistory ||
    DocumentProductCapability.recoverLocalUnpublishedEdits => true,
    DocumentProductCapability.createDocument ||
    DocumentProductCapability.publishNewEdit ||
    DocumentProductCapability.inviteCollaborator ||
    DocumentProductCapability.runWorkflowAutomation =>
      paidWorkEntitlementActive,
  };
}
