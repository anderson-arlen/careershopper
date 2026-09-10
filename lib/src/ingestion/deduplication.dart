import '../domain/job.dart';

enum DeduplicationDisposition { create, merge, reviewCandidate }

class DeduplicationDecision {
  const DeduplicationDecision(this.disposition, {this.reason});

  final DeduplicationDisposition disposition;
  final String? reason;
}

DeduplicationDecision compareListings(
  NormalizedListing incoming,
  NormalizedListing existing,
) {
  if (incoming.sourceFamily == existing.sourceFamily &&
      incoming.providerJobId != null &&
      incoming.providerJobId == existing.providerJobId) {
    return const DeduplicationDecision(
      DeduplicationDisposition.merge,
      reason: 'Exact provider job ID',
    );
  }

  if (incoming.tenantId != null &&
      incoming.tenantId == existing.tenantId &&
      incoming.requisitionId != null &&
      incoming.requisitionId == existing.requisitionId) {
    return const DeduplicationDecision(
      DeduplicationDisposition.merge,
      reason: 'Exact ATS tenant and requisition ID',
    );
  }

  if (incoming.applicationUrl != null &&
      incoming.applicationUrl == existing.applicationUrl) {
    return const DeduplicationDecision(
      DeduplicationDisposition.merge,
      reason: 'Exact canonical application URL',
    );
  }

  if (incoming.contentHash == existing.contentHash &&
      incoming.normalizedEmployerName == existing.normalizedEmployerName &&
      incoming.title.toLowerCase() == existing.title.toLowerCase() &&
      incoming.location.toLowerCase() == existing.location.toLowerCase()) {
    return const DeduplicationDecision(
      DeduplicationDisposition.merge,
      reason: 'Exact content and normalized identity fingerprint',
    );
  }

  if (incoming.normalizedEmployerName == existing.normalizedEmployerName &&
      incoming.title.toLowerCase() == existing.title.toLowerCase() &&
      incoming.location.toLowerCase() == existing.location.toLowerCase()) {
    return const DeduplicationDecision(
      DeduplicationDisposition.reviewCandidate,
      reason: 'Similar identity but different content',
    );
  }

  return const DeduplicationDecision(DeduplicationDisposition.create);
}
