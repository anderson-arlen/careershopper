part of 'database.dart';

class InterviewWorkspaces extends Table {
  TextColumn get jobId => text().references(Jobs, #id)();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  TextColumn get ladderJson => text().withDefault(const Constant('[]'))();
  BoolColumn get ladderEdited => boolean().withDefault(const Constant(false))();
  TextColumn get overridesJson => text().withDefault(const Constant('{}'))();
  TextColumn get intelId => text().nullable()();
  TextColumn get questionsId => text().nullable()();
  TextColumn get contextId => text().nullable()();
  TextColumn get preparationState =>
      text().withDefault(const Constant('needed'))();
  TextColumn get preparationError => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {jobId};
}

class InterviewRevisions extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text().references(Jobs, #id)();
  TextColumn get kind => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class InterviewPractices extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text().references(Jobs, #id)();
  TextColumn get stageId => text()();
  TextColumn get requestId => text().unique()();
  TextColumn get requestJson => text()();
  TextColumn get snapshotJson => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  TextColumn get debrief => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class InterviewExchanges extends Table {
  TextColumn get practiceId => text().references(InterviewPractices, #id)();
  TextColumn get exchangeId => text()();
  IntColumn get sequence => integer()();
  IntColumn get revision => integer().withDefault(const Constant(0))();
  TextColumn get payloadJson => text()();
  TextColumn get historyJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {practiceId, exchangeId};
}

class InterviewSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get autoPrepare => boolean().withDefault(const Constant(false))();
  TextColumn get agentId => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}
