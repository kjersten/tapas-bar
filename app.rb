require 'sinatra'
require 'fileutils'
require 'tempfile'
require "sinatra/reloader" if development?


enable :sessions
set :session_secret, ENV['RT_SESSION_SECRET']
set :protection, except: :session_hijacking

Episode = Struct.new(:num, :dir) do
  def self.all where = 'episodes'
    Dir.entries(where).map do |dir|
      if dir =~ /\A(\d+)/
        ep_num = $1.to_i
        self.new ep_num, File.join(where, dir)
      end
    end.compact.sort { |x,y| x.num <=> y.num }.reverse
  end

  def self.unwatched
    all.reject(&:watched?)
  end

  def self.find_by_number num
    all.find { |ep| ep.num == num.to_i }
  end

  def html
    @html ||= File.read File.join(dir, 'index.html')
  end

  def full_title
    html.match(/<h1>(.*)<\/h1>/)[1]
  end

  def number
    full_title.match(/(.*?):/)[1]
  end

  def title
    full_title.match(/(:\s*)(.*)/)[2]
  end

  def description
    html.match(/<p>(.*)<\/p>/)[1]
  end

  def video_url
    @url ||= File.read File.join(dir, 'video-url')
  end

  def local_video_url
    "media/#{File.basename video_url}"
  end

  def has_video?
    File.exist? "public/#{local_video_url}"
  end

  def watched_indicator
    File.join(dir, 'watched')
  end

  def watched?
    File.exist? watched_indicator
  end
end

helpers do
  def mark_as_watched_path episode
    "/watched/%d" % episode.num
  end

  def download_path episode
    "/download/%d" % episode.num
  end

  def all_eps?
    request.path_info == "/all"
  end
end

before do
  pass if ['/', '/login', '/tapas.css'].include?(request.path_info)

  unless session[:username] == ENV['RT_USER']
    redirect '/'
  end
end

get '/' do
  erb :login, locals: { login_failed: false }
end

post '/login' do
  username, password = params[:username], params[:password]
  if username == ENV['RT_USER'] && password == ENV['RT_PASS']
    session[:username] = username
    redirect "/unwatched"
  else
    erb :login, locals: { login_failed: true }
  end
end

get '/unwatched' do
  erb :index, locals: { episodes: Episode.unwatched }
end

get '/all' do
  erb :index, locals: { episodes: Episode.all }
end

post '/watched/:ep_num' do
  ep = Episode.find_by_number params[:ep_num]
  FileUtils.touch ep.watched_indicator
  redirect params[:redirect_to] || back
end

post '/download/:ep_num' do
  ep = Episode.find_by_number params[:ep_num]
  tracefile = Tempfile.new("#{ep.num}.trace")
  system %(./fetch "#{ep.video_url}" "public/#{ep.local_video_url}" --trace-ascii "#{tracefile.path}" &)
  "/download/progress?tracefile=#{tracefile.path}"
end

get '/download/progress' do
  total_bytes = 0
  received_bytes = 0

  File.open(params[:tracefile], 'r') do |trace|
    trace.each do |line|
      if line.start_with? "0000: "
        total_bytes = $1.to_i if line =~ /^0000: content-length: (\d+)/i
      elsif line.start_with? "<= Recv data" and line =~ /(\d+)/
        received_bytes += $1.to_i
      end
    end
  end

  (received_bytes / total_bytes.to_f).to_s
end

get '/tapas.css' do
  scss :style
end
