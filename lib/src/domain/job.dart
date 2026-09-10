import 'dart:typed_data';

// Shared by desktop evaluation prompts and the discoverable MCP contract.
const jobEvaluationScoringInstructions =
    '''Score the opportunity against the posting's stated requirements and responsibilities, using confirmed applicant facts and preferences. Personal fit measures alignment with that stated work; attainability measures supported qualification gaps and concrete hiring or practical barriers.
Missing detail is not a mismatch. Do not lower either score or impose a score ceiling merely because a posting is brief, vague, or omits technologies, responsibilities, seniority, compensation, or other details. Do not invent unstated requirements or assume the applicant lacks experience with an unspecified stack. When confirmed evidence meets the stated requirements, score that match strongly even if the posting is sparse.
Represent missing or ambiguous information in unknowns and confidence, separately from fit and attainability. Confidence measures certainty in the assessment, not suitability; it is not a score multiplier. Explain actual score deductions with specific evidence. Explicit contradictory requirements, confirmed skill gaps, or concrete conflicts with applicant constraints can affect the appropriate score; distinguish those from information that simply was not supplied. Never assume an unknown qualification is met or failed. A fully retrieved but terse posting can be evaluated; a failed or truncated retrieval must be reported rather than scored as a poor match.''';

enum JobAvailability { unknown, open, closed }

enum ReviewState {
  pendingEvaluation,
  inbox,
  hiddenBySearch,
  hiddenLowScore,
  approved,
  discarded,
}

enum ApplicationStatus {
  unknown,
  notApplied,
  readyToApply,
  applied,
  interviewing,
  offer,
  hired,
}

enum ApplicationOutcome { active, rejected, withdrawn, expired }

enum SourceHealthState {
  healthy,
  backoff,
  unavailableBlocked,
  unavailableCaptcha,
  authenticationRequired,
  disabled,
  error,
}

extension PersistedEnum on Enum {
  String get persistedName => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );
}

JobAvailability jobAvailabilityFromStorage(String value) =>
    JobAvailability.values.firstWhere(
      (candidate) => candidate.persistedName == value,
      orElse: () => JobAvailability.unknown,
    );

ReviewState reviewStateFromStorage(String value) =>
    ReviewState.values.firstWhere(
      (candidate) => candidate.persistedName == value,
      orElse: () => ReviewState.pendingEvaluation,
    );

ApplicationStatus applicationStatusFromStorage(String value) =>
    ApplicationStatus.values.firstWhere(
      (candidate) => candidate.persistedName == value,
      orElse: () => ApplicationStatus.notApplied,
    );

ApplicationOutcome applicationOutcomeFromStorage(String value) =>
    ApplicationOutcome.values.firstWhere(
      (candidate) => candidate.persistedName == value,
      orElse: () => ApplicationOutcome.active,
    );

typedef JobId = String;
typedef EmployerId = String;

class InboxJob {
  const InboxJob({
    required this.id,
    required this.title,
    required this.employerName,
    required this.location,
    required this.description,
    required this.applicationUrl,
    required this.availability,
    required this.reviewState,
    required this.applicationStatus,
    required this.observedAt,
    this.employerId,
    this.overallScore,
    this.personalFitScore,
    this.attainabilityScore,
    this.evaluationSummary,
    this.readyToApply = false,
    this.aiError,
    this.applicationOutcome = ApplicationOutcome.active,
    this.employerLogoPng,
    this.employerLogoSourceUrl,
  });

  final JobId id;
  final EmployerId? employerId;
  final String title;
  final String employerName;
  final String location;
  final String description;
  final Uri? applicationUrl;
  final JobAvailability availability;
  final ReviewState reviewState;
  final ApplicationStatus applicationStatus;
  final ApplicationOutcome applicationOutcome;
  final DateTime observedAt;
  final int? overallScore;
  final int? personalFitScore;
  final int? attainabilityScore;
  final String? evaluationSummary;
  final bool readyToApply;
  final String? aiError;
  final Uint8List? employerLogoPng;
  final String? employerLogoSourceUrl;
}

class NormalizedListing {
  const NormalizedListing({
    required this.sourceFamily,
    required this.adapterId,
    required this.providerJobId,
    required this.title,
    required this.employerName,
    required this.normalizedEmployerName,
    required this.location,
    required this.description,
    required this.contentHash,
    required this.sourceUrl,
    required this.applicationUrl,
    required this.observedAt,
    this.tenantId,
    this.requisitionId,
    this.remoteStatus,
    this.employmentType,
    this.compensationMinimum,
    this.compensationMaximum,
    this.compensationCurrency,
    this.rawPayloadJson,
  });

  final String sourceFamily;
  final String adapterId;
  final String? providerJobId;
  final String? tenantId;
  final String? requisitionId;
  final String? remoteStatus;
  final String? employmentType;
  final int? compensationMinimum;
  final int? compensationMaximum;
  final String? compensationCurrency;
  final String title;
  final String employerName;
  final String normalizedEmployerName;
  final String location;
  final String description;
  final String contentHash;
  final Uri sourceUrl;
  final Uri? applicationUrl;
  final DateTime observedAt;
  final String? rawPayloadJson;
}

class EvaluationResult {
  const EvaluationResult({
    required this.personalFitScore,
    required this.attainabilityScore,
    required this.confidence,
    required this.summary,
    required this.strengths,
    required this.concerns,
    required this.unknowns,
  });

  final int personalFitScore;
  final int attainabilityScore;
  final double confidence;
  final String summary;
  final List<String> strengths;
  final List<String> concerns;
  final List<String> unknowns;

  int get overallScore =>
      (personalFitScore * 0.60 + attainabilityScore * 0.40).round();
}
