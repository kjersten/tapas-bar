class Episode
  require_relative 'elasticsearch_client'
  extend ElasticsearchClient

  attr_accessor :number, :title, :description, :remote_video_url, :local_video_url, :watched
  alias_method :watched?, :watched

  def self.all
    parse(records_from_elasticsearch)
  end

  def self.unwatched
    parse(records_from_elasticsearch({ watched?: false }))
  end

  def self.find_by_number(num)
    parse(records_from_elasticsearch({ number: num })).first
  end

  def initialize(number, title, description, remote_video_url, local_video_url, watched)
    @number = number
    @title = title
    @description = description
    @remote_video_url = remote_video_url
    @local_video_url = local_video_url
    @watched = watched
  end

  def public_video_url
    "media/#{File.basename local_video_url}"
  end

  def has_video?
    File.exists?(local_video_url)
  end

  private

  def self.parse(elasticsearch_records)
    elasticsearch_records["hits"]["hits"].map do |hit|
      ep = hit["_source"]
      self.new(ep['number'], ep['title'], ep['description'], ep['remote_video_url'], ep['local_video_url'], ep['watched?'])
    end
  end
end
