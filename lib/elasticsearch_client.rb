module ElasticsearchClient
  def client
    Elasticsearch::Client.new log: true
  end

  def records_from_elasticsearch(options = {})
    client.search index: 'tapas', size: 400, body: formulate_query_string(options)
  end

  def formulate_query_string(options)
    if options.empty?
      {}
    else
      { query: { match: options } }
    end
  end
end
