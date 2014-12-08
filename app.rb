require 'sinatra'
require 'fileutils'
require 'tempfile'
require "sinatra/json"
require "elasticsearch"
require "sinatra/reloader" if development?
require_relative "lib/episode"

enable :sessions
set :session_secret, ENV['RT_SESSION_SECRET']
set :protection, except: :session_hijacking

helpers do
  def mark_as_watched_path episode
    "/watched/%d" % episode.number
  end

  def download_path episode
    "/download/%d" % episode.number
  end

  def all_eps?
    request.path_info == "/all"
  end

  def get_hash(episodes)
    episodes.map do |ep|
      {
        number: ep.number,
        title: ep.title,
        description: ep.description,
        actions: erb(:actions, locals: { ep: ep })
      }
    end
  end

  def time_it(operation_name, operation)
    start_time = Time.now
    operation.call
    end_time = Time.now
    puts "#{operation_name} operation took #{end_time - start_time} seconds"
  end
end

before do
  pass if ['/', '/login', '/tapas.css'].include?(request.path_info)

  unless session[:username] == ENV['RT_USER']
    redirect '/'
  end
end

get '/' do
  if session[:username] == ENV['RT_USER']
    redirect '/unwatched'
  end

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
  erb :index
end

get '/all' do
  erb :index
end

get '/list' do
  episodes = params[:all] ? Episode.all : Episode.unwatched
  json data: get_hash(episodes)
end

post '/watched/:ep_num' do
  ep = Episode.find_by_number params[:ep_num]
  client = Elasticsearch::Client.new log: true
  client.update index: 'tapas', type: 'episode', id: ep.number, body: { doc: { watched?: true } }
  redirect params[:redirect_to] || back
end

post '/download/:ep_num' do
  ep = Episode.find_by_number params[:ep_num]
  tracefile = Tempfile.new("#{ep.number}.trace")
  system %(./fetch "#{ep.remote_video_url}" "#{ep.local_video_url}" --trace-ascii "#{tracefile.path}" &)
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
