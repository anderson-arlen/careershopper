import '../domain/job.dart';
import '../sources/job_source_adapter.dart';

enum SearchFilterDisposition { match, plausibleUnknown, reject }

class SearchFilterResult {
  const SearchFilterResult(this.disposition, {this.reasons = const []});

  final SearchFilterDisposition disposition;
  final List<String> reasons;
}

SearchFilterResult enforceSavedSearch(
  NormalizedListing listing,
  SavedSearchQuery search,
) {
  final rejected = <String>[];
  final unknown = <String>[];
  final title = listing.title.toLowerCase();
  final description = listing.description.toLowerCase();

  if (search.includedTitles.isNotEmpty &&
      !search.includedTitles.any(
        (term) => title.contains(term.toLowerCase()),
      )) {
    rejected.add('title does not match included titles');
  }
  if (search.excludedTitles.any((term) => title.contains(term.toLowerCase()))) {
    rejected.add('title matches an excluded title');
  }

  if (search.includedKeywords.isNotEmpty) {
    if (description.isEmpty) {
      unknown.add('description is unavailable for keyword matching');
    } else if (!search.includedKeywords.any(
      (term) => description.contains(term.toLowerCase()),
    )) {
      rejected.add('description does not match included keywords');
    }
  }
  if (search.excludedKeywords.isNotEmpty) {
    if (description.isEmpty) {
      unknown.add('description is unavailable for exclusion matching');
    } else if (search.excludedKeywords.any(
      (term) => description.contains(term.toLowerCase()),
    )) {
      rejected.add('description matches an excluded keyword');
    }
  }

  if (search.locations.isNotEmpty) {
    if (listing.location.trim().isEmpty) {
      unknown.add('location is unavailable');
    } else if (!search.locations.any(
      (location) =>
          listing.location.toLowerCase().contains(location.toLowerCase()),
    )) {
      rejected.add('location does not match');
    }
  }

  if (search.remoteStatuses.isNotEmpty) {
    final remoteStatus = listing.remoteStatus?.toLowerCase();
    if (remoteStatus == null || remoteStatus.isEmpty) {
      unknown.add('remote status is unavailable');
    } else if (!search.remoteStatuses.any(
      (status) => remoteStatus == status.toLowerCase(),
    )) {
      rejected.add('remote status does not match');
    }
  }

  if (search.employmentTypes.isNotEmpty) {
    final employmentType = listing.employmentType?.toLowerCase();
    if (employmentType == null || employmentType.isEmpty) {
      unknown.add('employment type is unavailable');
    } else if (!search.employmentTypes.any(
      (type) => employmentType.contains(type.toLowerCase()),
    )) {
      rejected.add('employment type does not match');
    }
  }

  if (search.minimumCompensation != null) {
    if (listing.compensationMaximum == null ||
        listing.compensationCurrency == null) {
      unknown.add('compensation is unavailable');
    } else if (search.currency != null &&
        listing.compensationCurrency!.toLowerCase() !=
            search.currency!.toLowerCase()) {
      unknown.add('compensation currency differs');
    } else if (listing.compensationMaximum! < search.minimumCompensation!) {
      rejected.add('maximum compensation is below the configured floor');
    }
  }

  if (rejected.isNotEmpty) {
    return SearchFilterResult(
      SearchFilterDisposition.reject,
      reasons: rejected,
    );
  }
  if (unknown.isNotEmpty) {
    return SearchFilterResult(
      SearchFilterDisposition.plausibleUnknown,
      reasons: unknown,
    );
  }
  return const SearchFilterResult(SearchFilterDisposition.match);
}
