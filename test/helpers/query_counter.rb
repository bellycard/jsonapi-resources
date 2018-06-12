class QueryCounter
  attr_accessor :query_count

  IGNORED_SQL = [/^PRAGMA (?!(table_info))/, /^SELECT currval/, /^SELECT CAST/, /^SELECT @@IDENTITY/, /^SELECT @@ROWCOUNT/, /^SAVEPOINT/, /^ROLLBACK TO SAVEPOINT/, /^RELEASE SAVEPOINT/, /^SHOW max_identifier_length/]

  def initialize
    self.query_count = 0
  end

  def call(name, start, finish, message_id, values)
    # FIXME: this seems bad. we should probably have a better way to indicate
    # the query was cached
    unless 'CACHE' == values[:name]
      self.query_count += 1 unless IGNORED_SQL.any? { |r| values[:sql] =~ r }
    end
  end
end
