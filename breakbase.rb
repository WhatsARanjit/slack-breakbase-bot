#!/usr/bin/env ruby

require 'slack'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'

# Use a cookie written to filesystem if exists
def set_cookie
  if File.exist?('cookie.txt')
    puts 'Cookie exists'
    File.read('cookie.txt')
  else
    ''
  end
end

def yaml(file_path)
  YAML.load_file(file_path)
  rescue Exception => err
    puts "YAML invalid: #{file_path}"
    raise "#{err}"
end

# Moving user-specific data to yaml
@config            = yaml('config.yaml')
@channel           = @config['channel']            || '#general'
@breakbase_game_id = @config['breakbase_game_id']
@interval          = @config['interval']           || 600
@reminder          = @config['reminder']           || 21600
@token             = @config['token']

@breakbase_url     = "http://breakbase.com/#{@breakbase_game_id}"
@breakbase_enter   = "http://breakbase.com/room/#{@breakbase_game_id}/enter"
@breakbase_cookie  = set_cookie
@game_hash         = {}
@current_player    = ''
@timer             = 0

def current_player_id
  id = @game_hash['game']['turn']
  @game_hash['game']['players'][id]
end

def player_name(id)
  @game_hash['users'][id]['name']
end

def check_player(player)
  if player == @current_player
    return true
  else
    return false
  end
end

def check_new_game
  if @game_hash['request']['type'] == 'new_game'
    return true
  else
    return false
  end
end

def get_cookie(set_cookie_string)
  #set_cookie_string.split('; ')[0].gsub(/breakbase=/, '')
  set_cookie_string.split('; ')[0]
end

def write_cookie
 File.open('cookie.txt', 'w') { |file| file.write(@breakbase_cookie) }
end

def bbase_get(uri_str)
  uri           = URI(uri_str)
  req           = Net::HTTP::Get.new(uri_str)
  req['Cookie'] = @breakbase_cookie

  bb_res = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(req)
  end
end

def bbase_post(uri_str)
  uri               = URI(uri_str)
  req               = Net::HTTP::Post.new(uri_str)
  req['Cookie']     = @breakbase_cookie

  req.set_form_data({
    'anon' => 'Enter anonymously!'
  })

  bb_res = Net::HTTP.start(uri.hostname, uri.port) do |http|
    http.request(req)
  end
end

def parse_html(html)
  # Grab the JSON part and cut off the notes (not real JSON)
  cleanup1 = html.match(/RoomMgr\.create\((.*)\)/)[1]
  cleanup2 = cleanup1.split(',', 3)[2].gsub(/, \[{"msg":.*/, '')
  cleanup  = cleanup2.gsub(/, \[{"note":.*/, '')
  JSON.parse(cleanup)
end

def find_mention(player)
  if @config['mentions'][player]
    " <@#{@config['mentions'][player]}>"
  else
    nil
  end
end

def notify_chat(player)
  Slack.configure do |config|
    config.token = @token
  end

  client = Slack::Client.new

  message = {
    :channel  => @channel,
    :username => 'breakbase',
    :icon_url => 'https://pbs.twimg.com/profile_images/1364067224/icon.jpg',
    :text     => "It's #{player}'s turn on BreakBase: #{@breakbase_url}#{find_mention(player)}",
  }

  client.chat_postMessage(message)
  #client.auth_test
  @timer = 0
end

def notify_new
  Slack.configure do |config|
    config.token = @token
  end

  client     = Slack::Client.new
  list_ids   = @game_hash['seated'] - @game_hash['request']['responses']
  list_names = ''

  list_ids.each do |id|
    list_names = "#{list_names}#{find_mention(player_name(id))}"
  end

  message = {
    :channel  => @channel,
    :username => 'breakbase',
    :icon_url => 'https://pbs.twimg.com/profile_images/1364067224/icon.jpg',
    :text     => "New game on BreakBase: #{@breakbase_url}#{list_names}",
  }

  client.chat_postMessage(message)
  #client.auth_test
  @timer = 0
  return list_names
end

def do_it
  if @breakbase_cookie == ''
    anon_prompt       = bbase_get(@breakbase_enter)
    @breakbase_cookie = get_cookie(anon_prompt['Set-Cookie'])
    enter_button      = bbase_post(@breakbase_enter)
    @breakbase_cookie = get_cookie(enter_button['Set-Cookie'])
  end
  get_game            = bbase_get(@breakbase_url)
  #puts get_game.code

  # If successful login, remember cookie
  if get_game.code == '200'
    write_cookie
  else
    @breakbase_cookie == ''
  end

  @game_hash = parse_html(get_game.body)
  if check_new_game
    puts "New game; notified:#{notify_new}"
  elsif ! check_player(current_player_id)
    @current_player = current_player_id
    notify_chat(player_name(current_player_id))
    puts "New current player: #{player_name(current_player_id)}"
  elsif @timer >= @reminder
    notify_chat(player_name(current_player_id))
    puts "Reminded player: #{player_name(current_player_id)}"
  else
    puts "Current player: #{player_name(current_player_id)}"
  end
end

while true do
  begin
    do_it
  rescue Exception => e
    puts e.message
    puts e.backtrace.inspect
  else
    sleep @interval
    @timer += @interval
  end
end
