import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'app_data_directory.dart';

part 'database.g.dart';
part 'interview_tables.dart';

@DataClassName('SavedSearchRow')
class SavedSearches extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get pollIntervalMinutes =>
      integer().withDefault(const Constant(60))();
  TextColumn get scheduleCron => text().nullable()();
  DateTimeColumn get nextScheduledAt => dateTime().nullable()();
  TextColumn get lastScheduleError => text().nullable()();
  IntColumn get scoreThreshold => integer().withDefault(const Constant(70))();
  TextColumn get queryJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SourceConfigRow')
class SourceConfigs extends Table {
  TextColumn get id => text()();
  TextColumn get sourceFamily => text()();
  TextColumn get adapterId => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get useFixedProxy =>
      boolean().withDefault(const Constant(false))();
  TextColumn get configJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SavedSearchSourceRow')
class SavedSearchSources extends Table {
  TextColumn get savedSearchId =>
      text().references(SavedSearches, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceConfigId =>
      text().references(SourceConfigs, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {savedSearchId, sourceConfigId};
}

@DataClassName('SourceHealthRow')
class SourceHealthRecords extends Table {
  TextColumn get sourceConfigId =>
      text().references(SourceConfigs, #id, onDelete: KeyAction.cascade)();
  TextColumn get state => text().withDefault(const Constant('healthy'))();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get backoffUntil => dateTime().nullable()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {sourceConfigId};
}

@DataClassName('SearchRunRow')
class SearchRuns extends Table {
  TextColumn get diagnosticsJson => text().nullable()();
  TextColumn get id => text()();
  TextColumn get savedSearchId => text().references(SavedSearches, #id)();
  TextColumn get sourceConfigId => text().references(SourceConfigs, #id)();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get observationsSeen => integer().withDefault(const Constant(0))();
  TextColumn get detail => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EmployerRow')
class Employers extends Table {
  BlobColumn get logoPng => blob().nullable()();
  TextColumn get logoSourceUrl => text().nullable()();
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get normalizedName => text()();
  TextColumn get websiteDomain => text().nullable()();
  DateTimeColumn get blockedAt => dateTime().nullable()();
  TextColumn get blockReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('EmployerAliasRow')
class EmployerAliases extends Table {
  TextColumn get id => text()();
  TextColumn get employerId =>
      text().references(Employers, #id, onDelete: KeyAction.cascade)();
  TextColumn get displayName => text()();
  TextColumn get normalizedName => text()();
  TextColumn get sourceFamily => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {employerId, normalizedName},
  ];
}

@DataClassName('JobRow')
class Jobs extends Table {
  DateTimeColumn get stateChangedAt => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get id => text()();
  TextColumn get employerId => text().nullable().references(Employers, #id)();
  TextColumn get currentSnapshotId => text().nullable()();
  TextColumn get currentEvaluationId => text().nullable()();
  TextColumn get availability =>
      text().withDefault(const Constant('unknown'))();
  TextColumn get reviewState =>
      text().withDefault(const Constant('pending_evaluation'))();
  DateTimeColumn get firstSeenAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('JobSnapshotRow')
class JobSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get jobId =>
      text().references(Jobs, #id, onDelete: KeyAction.cascade)();
  IntColumn get revision => integer()();
  TextColumn get title => text()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get remoteStatus => text().nullable()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get descriptionHash => text()();
  TextColumn get applicationUrl => text().nullable()();
  TextColumn get compensationJson => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {jobId, revision},
  ];
}

@DataClassName('JobIdentityKeyRow')
class JobIdentityKeys extends Table {
  TextColumn get id => text()();
  TextColumn get jobId =>
      text().references(Jobs, #id, onDelete: KeyAction.cascade)();
  TextColumn get keyType => text()();
  TextColumn get keyValue => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {keyType, keyValue},
  ];
}

@DataClassName('JobObservationRow')
class JobObservations extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  TextColumn get sourceFamily => text()();
  TextColumn get adapterId => text()();
  TextColumn get providerJobId => text().nullable()();
  TextColumn get tenantId => text().nullable()();
  TextColumn get requisitionId => text().nullable()();
  TextColumn get sourceUrl => text()();
  TextColumn get canonicalApplicationUrl => text().nullable()();
  TextColumn get rawPayloadJson => text().nullable()();
  TextColumn get payloadHash => text()();
  DateTimeColumn get observedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('JobSearchMatchRow')
class JobSearchMatches extends Table {
  TextColumn get jobId =>
      text().references(Jobs, #id, onDelete: KeyAction.cascade)();
  TextColumn get savedSearchId =>
      text().references(SavedSearches, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get firstMatchedAt => dateTime()();
  DateTimeColumn get lastMatchedAt => dateTime()();
  TextColumn get disposition => text().withDefault(const Constant('match'))();
  TextColumn get reasonsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column<Object>> get primaryKey => {jobId, savedSearchId};
}

@DataClassName('CareerSourceRow')
class CareerSources extends Table {
  TextColumn get id => text()();
  TextColumn get sourceType => text()();
  TextColumn get label => text()();
  TextColumn get locator => text().nullable()();
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CareerFactRow')
class CareerFacts extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get currentRevisionId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CareerFactRevisionRow')
class CareerFactRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get factId =>
      text().references(CareerFacts, #id, onDelete: KeyAction.cascade)();
  IntColumn get revision => integer()();
  TextColumn get valueJson => text()();
  TextColumn get verificationStatus => text()();
  TextColumn get visibility => text()();
  TextColumn get sourceId => text().nullable().references(CareerSources, #id)();
  TextColumn get evidenceText => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {factId, revision},
  ];
}

@DataClassName('CareerPreferenceRow')
class CareerPreferences extends Table {
  TextColumn get id => text()();
  TextColumn get key => text().unique()();
  TextColumn get valueJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProfileSnapshotRow')
class ProfileSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get manifestJson => text()();
  TextColumn get manifestHash => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiHarnessProfileRow')
class AiHarnessProfiles extends Table {
  BoolColumn get isJobMatchingDefault =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isApplicationWritingDefault =>
      boolean().withDefault(const Constant(false))();
  TextColumn get configValuesJson => text().withDefault(const Constant('{}'))();
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get executable => text()();
  TextColumn get argumentsJson => text().withDefault(const Constant('[]'))();
  TextColumn get protocol =>
      text().withDefault(const Constant('legacy_process'))();
  TextColumn get registryAgentId => text().nullable()();
  TextColumn get registryVersion => text().nullable()();
  TextColumn get distributionType => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AcpRegistryCacheRow')
class AcpRegistryCache extends Table {
  TextColumn get id => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiWorkOrderRow')
class AiWorkOrders extends Table {
  TextColumn get jobId => text().nullable().references(Jobs, #id)();
  TextColumn get configValuesJson => text().withDefault(const Constant('{}'))();
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get scopeJson => text()();
  TextColumn get agentId => text().nullable()();
  TextColumn get acpSessionId => text().nullable()();
  TextColumn get title => text().withDefault(const Constant('AI activity'))();
  TextColumn get promptVersion => text()();
  DateTimeColumn get leasedUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AiActivityEntryRow')
class AiActivityEntries extends Table {
  TextColumn get id => text()();
  TextColumn get workOrderId =>
      text().references(AiWorkOrders, #id, onDelete: KeyAction.cascade)();
  TextColumn get externalId => text().nullable()();
  TextColumn get role => text()();
  TextColumn get kind => text()();
  TextColumn get content =>
      text().named('text').withDefault(const Constant(''))();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  TextColumn get status => text().nullable()();
  IntColumn get sequence => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {workOrderId, externalId},
  ];
}

@DataClassName('AiWorkItemRow')
class AiWorkItems extends Table {
  TextColumn get id => text()();
  TextColumn get workOrderId =>
      text().references(AiWorkOrders, #id, onDelete: KeyAction.cascade)();
  TextColumn get subjectId => text()();
  TextColumn get status => text()();
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get error => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('JobEvaluationRow')
class JobEvaluations extends Table {
  TextColumn get id => text()();
  TextColumn get jobSnapshotId => text().references(JobSnapshots, #id)();
  TextColumn get profileSnapshotId =>
      text().references(ProfileSnapshots, #id)();
  TextColumn get workOrderId =>
      text().nullable().references(AiWorkOrders, #id)();
  IntColumn get personalFitScore => integer()();
  IntColumn get attainabilityScore => integer()();
  IntColumn get overallScore => integer()();
  RealColumn get confidence => real()();
  TextColumn get dimensionsJson => text()();
  TextColumn get strengthsJson => text()();
  TextColumn get concernsJson => text()();
  TextColumn get unknownsJson => text()();
  TextColumn get summary => text()();
  TextColumn get evidenceJson => text()();
  TextColumn get promptVersion => text()();
  TextColumn get agentJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ApplicationRow')
class Applications extends Table {
  TextColumn get outcome => text().withDefault(const Constant('active'))();
  TextColumn get id => text()();
  TextColumn get jobId => text().references(Jobs, #id)();
  TextColumn get status => text().withDefault(const Constant('not_applied'))();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  DateTimeColumn get appliedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {jobId},
  ];
}

@DataClassName('ApplicationEventRow')
class ApplicationEvents extends Table {
  TextColumn get id => text()();
  TextColumn get applicationId =>
      text().references(Applications, #id, onDelete: KeyAction.cascade)();
  TextColumn get previousStatus => text().nullable()();
  TextColumn get newStatus => text()();
  TextColumn get actor => text()();
  TextColumn get origin => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DocumentTemplateRow')
class DocumentTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get documentKind => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get formatVersion => integer().withDefault(const Constant(1))();
  TextColumn get settingsJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaterialSetRow')
class MaterialSets extends Table {
  BoolColumn get staged => boolean().withDefault(const Constant(false))();
  TextColumn get workOrderId =>
      text().nullable().references(AiWorkOrders, #id)();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  TextColumn get id => text()();
  TextColumn get applicationId => text().references(Applications, #id)();
  TextColumn get jobSnapshotId => text().references(JobSnapshots, #id)();
  TextColumn get profileSnapshotId =>
      text().references(ProfileSnapshots, #id)();
  TextColumn get resumeMarkdown => text()();
  TextColumn get coverLetterMarkdown => text().nullable()();
  TextColumn get rendererVersion => text()();
  TextColumn get templateId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MaterialClaimRow')
class MaterialClaims extends Table {
  TextColumn get id => text()();
  TextColumn get materialSetId =>
      text().references(MaterialSets, #id, onDelete: KeyAction.cascade)();
  TextColumn get documentKind => text()();
  TextColumn get blockText => text()();
  TextColumn get factRevisionIdsJson => text()();
  TextColumn get jobEvidenceJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ArtifactRow')
class Artifacts extends Table {
  TextColumn get id => text()();
  TextColumn get materialSetId =>
      text().references(MaterialSets, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  TextColumn get relativePath => text()();
  TextColumn get sha256 => text()();
  TextColumn get mimeType => text()();
  IntColumn get byteLength => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('AuditEventRow')
class AuditEvents extends Table {
  IntColumn get sequence => integer().autoIncrement()();
  TextColumn get id => text().unique()();
  TextColumn get eventType => text()();
  TextColumn get subjectType => text()();
  TextColumn get subjectId => text()();
  TextColumn get actor => text()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get occurredAt => dateTime()();
}

@DriftDatabase(
  tables: [
    SavedSearches,
    SourceConfigs,
    SavedSearchSources,
    SourceHealthRecords,
    SearchRuns,
    Employers,
    EmployerAliases,
    Jobs,
    JobSnapshots,
    JobIdentityKeys,
    JobObservations,
    JobSearchMatches,
    CareerSources,
    CareerFacts,
    CareerFactRevisions,
    CareerPreferences,
    ProfileSnapshots,
    AiHarnessProfiles,
    AcpRegistryCache,
    AiWorkOrders,
    AiWorkItems,
    AiActivityEntries,
    JobEvaluations,
    Applications,
    ApplicationEvents,
    DocumentTemplates,
    MaterialSets,
    MaterialClaims,
    Artifacts,
    AuditEvents,
    InterviewWorkspaces,
    InterviewRevisions,
    InterviewPractices,
    InterviewExchanges,
    InterviewSettings,
  ],
)
class CareerShopperDatabase extends _$CareerShopperDatabase {
  CareerShopperDatabase(super.executor);

  CareerShopperDatabase.openDefault()
    : super(_openDatabase(careerShopperDataDirectory()));

  // Track the state axes at the database boundary so UI, MCP, and background
  // writers behave identically. Content refreshes and no-op writes are excluded.
  Future<void> _createStateChangeTriggers() async {
    await customStatement("""
      CREATE TRIGGER IF NOT EXISTS job_state_changed
      AFTER UPDATE OF review_state, availability ON jobs
      WHEN OLD.review_state IS NOT NEW.review_state OR OLD.availability IS NOT NEW.availability
      BEGIN UPDATE jobs SET state_changed_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE id = NEW.id; END
    """);
    await customStatement("""
      CREATE TRIGGER IF NOT EXISTS application_state_created
      AFTER INSERT ON applications
      BEGIN UPDATE jobs SET state_changed_at = MAX(COALESCE(state_changed_at, first_seen_at), NEW.updated_at) WHERE id = NEW.job_id; END
    """);
    await customStatement("""
      CREATE TRIGGER IF NOT EXISTS application_state_changed
      AFTER UPDATE OF status, outcome, approved_at ON applications
      WHEN OLD.status IS NOT NEW.status OR OLD.outcome IS NOT NEW.outcome OR OLD.approved_at IS NOT NEW.approved_at
      BEGIN UPDATE jobs SET state_changed_at = MAX(COALESCE(state_changed_at, first_seen_at), NEW.updated_at) WHERE id = NEW.job_id; END
    """);
    await customStatement("""
      CREATE TRIGGER IF NOT EXISTS employer_block_state_changed
      AFTER UPDATE OF blocked_at ON employers
      WHEN (OLD.blocked_at IS NULL) != (NEW.blocked_at IS NULL)
      BEGIN UPDATE jobs SET state_changed_at = CAST(strftime('%s', 'now') AS INTEGER) WHERE employer_id = NEW.id; END
    """);
  }

  Future<void> _createReadIndexes() async {
    for (final sql in const [
      'CREATE INDEX IF NOT EXISTS job_observation_lookup ON job_observations(job_id, observed_at)',
      'CREATE INDEX IF NOT EXISTS job_employer_lookup ON jobs(employer_id)',
      'CREATE INDEX IF NOT EXISTS job_list_order ON jobs(last_seen_at DESC, id)',
      'CREATE INDEX IF NOT EXISTS work_order_job_kind ON ai_work_orders(job_id, kind, created_at DESC, id DESC)',
      'CREATE INDEX IF NOT EXISTS work_order_activity_order ON ai_work_orders(updated_at DESC, id DESC)',
      'CREATE INDEX IF NOT EXISTS work_order_pending ON ai_work_orders(kind, status)',
      'CREATE INDEX IF NOT EXISTS work_item_order ON ai_work_items(work_order_id, subject_id)',
      'CREATE INDEX IF NOT EXISTS work_item_subject ON ai_work_items(subject_id, work_order_id, status)',
      'CREATE INDEX IF NOT EXISTS activity_sequence ON ai_activity_entries(work_order_id, sequence, id)',
      'CREATE INDEX IF NOT EXISTS material_application ON material_sets(application_id, staged)',
      'CREATE INDEX IF NOT EXISTS interview_revision_job ON interview_revisions(job_id, created_at DESC, id DESC)',
      'CREATE INDEX IF NOT EXISTS interview_practice_job ON interview_practices(job_id, created_at DESC, id DESC)',
      'CREATE INDEX IF NOT EXISTS interview_exchange_order ON interview_exchanges(practice_id, sequence)',
    ]) {
      await customStatement(sql);
    }
  }

  @override
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createReadIndexes();
      await _createStateChangeTriggers();
      await customStatement(
        'CREATE UNIQUE INDEX saved_search_single_source '
        'ON saved_search_sources(saved_search_id)',
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 15) {
        final jobColumns = await customSelect(
          "PRAGMA table_info('jobs')",
        ).get();
        if (!jobColumns.any((row) => row.data['name'] == 'notes')) {
          await migrator.addColumn(jobs, jobs.notes);
        }
        if (from >= 4) {
          final orderColumns = await customSelect(
            "PRAGMA table_info('ai_work_orders')",
          ).get();
          if (!orderColumns.any((row) => row.data['name'] == 'job_id')) {
            await migrator.addColumn(aiWorkOrders, aiWorkOrders.jobId);
          }
        }
      }
      if (from >= 4 && from < 14) {
        final columns = await customSelect(
          "PRAGMA table_info('ai_harness_profiles')",
        ).get();
        for (final column in [
          aiHarnessProfiles.isJobMatchingDefault,
          aiHarnessProfiles.isApplicationWritingDefault,
        ]) {
          if (!columns.any((row) => row.data['name'] == column.name)) {
            await migrator.addColumn(aiHarnessProfiles, column);
          }
        }
      }
      if (from < 13) {
        final columns = await customSelect(
          "PRAGMA table_info('search_runs')",
        ).get();
        if (!columns.any((row) => row.data['name'] == 'diagnostics_json')) {
          await migrator.addColumn(searchRuns, searchRuns.diagnosticsJson);
        }
      }
      if (from < 12) {
        final columns = await customSelect(
          "PRAGMA table_info('applications')",
        ).get();
        if (!columns.any((row) => row.data['name'] == 'outcome')) {
          await migrator.addColumn(applications, applications.outcome);
        }
        // Recover the last recorded stage, not an assumed interview/application.
        // Legacy events remain unchanged as the original audit trail.
        await customStatement('''
          UPDATE applications
          SET outcome = status,
              status = COALESCE((
                SELECT stage FROM (
                  SELECT new_status AS stage, occurred_at, id, 1 AS position
                  FROM application_events WHERE application_id = applications.id
                  UNION ALL
                  SELECT previous_status AS stage, occurred_at, id, 0 AS position
                  FROM application_events WHERE application_id = applications.id
                )
                WHERE stage IN ('not_applied', 'ready_to_apply', 'applied',
                                'interviewing', 'offer', 'hired')
                ORDER BY occurred_at DESC, id DESC, position DESC LIMIT 1
              ), CASE WHEN applied_at IS NOT NULL THEN 'applied' ELSE 'unknown' END)
          WHERE status IN ('rejected', 'withdrawn')
        ''');
      }
      if (from < 2) {
        // v1 accidentally limited each adapter to one configured employer.
        // Rebuild only this table while preserving IDs used by its children.
        await customStatement('PRAGMA legacy_alter_table = ON');
        await customStatement(
          'ALTER TABLE source_configs RENAME TO source_configs_v1',
        );
        await customStatement('''
          CREATE TABLE source_configs (
            id TEXT NOT NULL PRIMARY KEY,
            source_family TEXT NOT NULL,
            adapter_id TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
            use_fixed_proxy INTEGER NOT NULL DEFAULT 0
              CHECK (use_fixed_proxy IN (0, 1)),
            config_json TEXT NOT NULL DEFAULT '{}',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await customStatement('''
          INSERT INTO source_configs
            (id, source_family, adapter_id, enabled, use_fixed_proxy,
             config_json, created_at, updated_at)
          SELECT id, source_family, adapter_id, enabled, use_fixed_proxy,
                 config_json, created_at, updated_at
          FROM source_configs_v1
        ''');
        await customStatement('DROP TABLE source_configs_v1');
        await customStatement('PRAGMA legacy_alter_table = OFF');
      }
      if (from < 3) {
        await migrator.createTable(documentTemplates);
      }
      if (from < 4) {
        await migrator.createTable(aiHarnessProfiles);
      }
      if (from < 5) {
        // Databases older than v4 create the current table above, so only a
        // genuine v4 database needs the new ACP columns added in place.
        if (from >= 4) {
          await migrator.addColumn(
            aiHarnessProfiles,
            aiHarnessProfiles.protocol,
          );
          await migrator.addColumn(
            aiHarnessProfiles,
            aiHarnessProfiles.registryAgentId,
          );
          await migrator.addColumn(
            aiHarnessProfiles,
            aiHarnessProfiles.registryVersion,
          );
          await migrator.addColumn(
            aiHarnessProfiles,
            aiHarnessProfiles.distributionType,
          );
        }
        await migrator.createTable(acpRegistryCache);
      }
      if (from < 6) {
        final columns = await customSelect(
          "PRAGMA table_info('ai_work_orders')",
        ).get();
        final names = columns
            .map((row) => row.data['name']?.toString())
            .whereType<String>()
            .toSet();
        if (!names.contains('acp_session_id')) {
          await migrator.addColumn(aiWorkOrders, aiWorkOrders.acpSessionId);
        }
        if (!names.contains('title')) {
          await migrator.addColumn(aiWorkOrders, aiWorkOrders.title);
        }
        await migrator.createTable(aiActivityEntries);
      }
      if (from < 8) {
        final profileColumns = await customSelect(
          "PRAGMA table_info('ai_harness_profiles')",
        ).get();
        if (!profileColumns.any(
          (row) => row.data['name'] == 'config_values_json',
        )) {
          await migrator.addColumn(
            aiHarnessProfiles,
            aiHarnessProfiles.configValuesJson,
          );
        }
        final orderColumns = await customSelect(
          "PRAGMA table_info('ai_work_orders')",
        ).get();
        if (!orderColumns.any(
          (row) => row.data['name'] == 'config_values_json',
        )) {
          await migrator.addColumn(aiWorkOrders, aiWorkOrders.configValuesJson);
        }
      }
      if (from < 9) {
        final columns = await customSelect(
          "PRAGMA table_info('material_sets')",
        ).get();
        if (!columns.any((row) => row.data['name'] == 'work_order_id')) {
          await migrator.addColumn(materialSets, materialSets.workOrderId);
        }
        if (!columns.any((row) => row.data['name'] == 'reviewed_at')) {
          await migrator.addColumn(materialSets, materialSets.reviewedAt);
        }
      }
      if (from < 10) {
        final columns = await customSelect(
          "PRAGMA table_info('material_sets')",
        ).get();
        if (!columns.any((row) => row.data['name'] == 'staged')) {
          await migrator.addColumn(materialSets, materialSets.staged);
        }
      }
      if (from < 11) {
        final columns = await customSelect(
          "PRAGMA table_info('employers')",
        ).get();
        if (!columns.any((row) => row.data['name'] == 'logo_png')) {
          await migrator.addColumn(employers, employers.logoPng);
        }
        if (!columns.any((row) => row.data['name'] == 'logo_source_url')) {
          await migrator.addColumn(employers, employers.logoSourceUrl);
        }
      }
      if (from < 7) {
        final orders = await select(aiWorkOrders).get();
        for (final order in orders) {
          if (order.kind != 'manual_job_import' ||
              (order.title.length <= 120 &&
                  !order.title.startsWith('Use the CareerShopper skill'))) {
            continue;
          }
          String host = 'job';
          try {
            final scope = jsonDecode(order.scopeJson);
            if (scope is Map && scope['url'] is String) {
              host = Uri.tryParse(scope['url']! as String)?.host ?? host;
            }
          } on FormatException {
            // Keep the generic title when legacy scope JSON is malformed.
          }
          await (update(
            aiWorkOrders,
          )..where((row) => row.id.equals(order.id))).write(
            AiWorkOrdersCompanion(
              title: Value('Import $host listing'),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
        }
      }
      if (from < 16) {
        final columns = await customSelect("PRAGMA table_info('jobs')").get();
        if (!columns.any((row) => row.data['name'] == 'state_changed_at')) {
          await migrator.addColumn(jobs, jobs.stateChangedAt);
        }
        // Recover known state dates without treating a listing refresh as a change.
        await customStatement("""
          UPDATE jobs SET state_changed_at = MAX(first_seen_at,
            COALESCE((SELECT MAX(updated_at) FROM applications a WHERE a.job_id = jobs.id), first_seen_at),
            COALESCE((SELECT MAX(ev.occurred_at) FROM application_events ev JOIN applications a ON a.id = ev.application_id WHERE a.job_id = jobs.id), first_seen_at),
            COALESCE((SELECT MAX(occurred_at) FROM audit_events WHERE subject_type = 'job' AND subject_id = jobs.id AND event_type = 'job.review_state_changed'), first_seen_at),
            COALESCE((SELECT created_at FROM job_evaluations WHERE id = jobs.current_evaluation_id), first_seen_at),
            COALESCE((SELECT MAX(occurred_at) FROM audit_events WHERE subject_type = 'employer' AND subject_id = jobs.employer_id AND event_type IN ('employer.blocked', 'employer.unblocked')), first_seen_at),
            COALESCE((SELECT blocked_at FROM employers WHERE id = jobs.employer_id), first_seen_at)
          ) WHERE state_changed_at IS NULL
        """);
        await _createStateChangeTriggers();
      }
      if (from < 17) {
        final columns = await customSelect(
          "PRAGMA table_info('saved_searches')",
        ).get();
        for (final column in [
          savedSearches.scheduleCron,
          savedSearches.nextScheduledAt,
          savedSearches.lastScheduleError,
        ]) {
          if (!columns.any((row) => row.data['name'] == column.name)) {
            await migrator.addColumn(savedSearches, column);
          }
        }
        final searches = await select(savedSearches).get();
        for (final search in searches) {
          final bindings =
              await (select(savedSearchSources)
                    ..where((r) => r.savedSearchId.equals(search.id))
                    ..orderBy([(r) => OrderingTerm.asc(r.sourceConfigId)]))
                  .get();
          for (final binding in bindings.skip(1)) {
            final source = await (select(
              sourceConfigs,
            )..where((r) => r.id.equals(binding.sourceConfigId))).getSingle();
            final config = jsonDecode(source.configJson) as Map;
            final label = config['employer_name'] ?? source.sourceFamily;
            final newId = const Uuid().v7();
            await into(savedSearches).insert(
              search
                  .toCompanion(false)
                  .copyWith(
                    id: Value(newId),
                    name: Value('${search.name} · $label'),
                  ),
            );
            await (update(savedSearchSources)..where(
                  (r) =>
                      r.savedSearchId.equals(search.id) &
                      r.sourceConfigId.equals(source.id),
                ))
                .write(
                  SavedSearchSourcesCompanion(savedSearchId: Value(newId)),
                );
            await (update(searchRuns)..where(
                  (r) =>
                      r.savedSearchId.equals(search.id) &
                      r.sourceConfigId.equals(source.id),
                ))
                .write(SearchRunsCompanion(savedSearchId: Value(newId)));
            // Keep historical matches available to both searches; no job is lost.
            await customStatement(
              'INSERT INTO job_search_matches '
              '(job_id, saved_search_id, first_matched_at, last_matched_at, disposition, reasons_json) '
              'SELECT job_id, ?, first_matched_at, last_matched_at, disposition, reasons_json '
              'FROM job_search_matches WHERE saved_search_id = ?',
              [newId, search.id],
            );
          }
        }
        await customStatement(
          'UPDATE saved_searches SET enabled = 0 WHERE NOT EXISTS '
          '(SELECT 1 FROM saved_search_sources WHERE saved_search_id = saved_searches.id)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS saved_search_single_source '
          'ON saved_search_sources(saved_search_id)',
        );
      }
      if (from < 18) {
        final existingTables = (await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).get()).map((r) => r.read<String>('name')).toSet();
        for (final table in <TableInfo>[
          interviewWorkspaces,
          interviewRevisions,
          interviewPractices,
          interviewExchanges,
          interviewSettings,
        ]) {
          if (!existingTables.contains(table.actualTableName)) {
            await migrator.createTable(table);
          }
        }
        await customStatement(
          "INSERT OR IGNORE INTO interview_workspaces (job_id, updated_at) SELECT job_id, updated_at FROM applications WHERE status = 'interviewing'",
        );
      }
      if (from < 19) await _createReadIndexes();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
    },
  );
}

LazyDatabase _openDatabase(Directory directory) {
  return LazyDatabase(() async {
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'careershopper.sqlite3'));
    return NativeDatabase.createInBackground(file);
  });
}
